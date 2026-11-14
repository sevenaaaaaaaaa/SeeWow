//! 外挂字幕解析与编码判定（M3 · T-11）。
//!
//! 只做两件事：**把字节变成可读文本**（编码判定），**把文本变成时间轴**（SRT / VTT）。
//! 渲染、字号、描边属于播放器层，不在这里。
//!
//! 依赖纪律：不引第三方编码库。UTF-8 与带 BOM 的 UTF-16 是确定能读的；GBK/BIG5
//! 这类没有 BOM 的老字幕直接返回 `Unsupported`，并告诉用户该转成 UTF-8——比猜错
//! 编码显示一屏乱码诚实。

use crate::error::{Error, Result};

/// 字幕文件格式。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubtitleFormat {
    Srt,
    Vtt,
}

impl SubtitleFormat {
    /// 按扩展名判断；未知扩展名返回 `None`，交给内容嗅探。
    pub fn from_extension(ext: &str) -> Option<Self> {
        match ext.trim_start_matches('.').to_lowercase().as_str() {
            "srt" => Some(Self::Srt),
            "vtt" | "webvtt" => Some(Self::Vtt),
            _ => None,
        }
    }
}

/// 文本编码。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Encoding {
    Utf8,
    Utf16Le,
    Utf16Be,
}

/// 一条字幕。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cue {
    pub start_ms: i64,
    pub end_ms: i64,
    pub text: String,
}

/// 判定编码：只认 BOM 与合法 UTF-8，其余一律拒绝。
pub fn detect_encoding(bytes: &[u8]) -> Result<Encoding> {
    if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        return Ok(Encoding::Utf8);
    }
    if bytes.starts_with(&[0xFF, 0xFE]) {
        return Ok(Encoding::Utf16Le);
    }
    if bytes.starts_with(&[0xFE, 0xFF]) {
        return Ok(Encoding::Utf16Be);
    }
    // 无 BOM：UTF-8 严格解码成功才算 UTF-8。
    match std::str::from_utf8(bytes) {
        Ok(_) => Ok(Encoding::Utf8),
        Err(_) => Err(Error::Unsupported(
            "字幕不是 UTF-8/UTF-16，请转成 UTF-8 后再试".to_string(),
        )),
    }
}

/// 按判定结果解码成字符串；去掉 BOM，统一换行到 `\n`。
pub fn decode(bytes: &[u8]) -> Result<(Encoding, String)> {
    let encoding = detect_encoding(bytes)?;
    let text = match encoding {
        Encoding::Utf8 => {
            let body = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(bytes);
            String::from_utf8(body.to_vec())
                .map_err(|_| Error::Parse("UTF-8 字幕含有非法字节".to_string()))?
        }
        Encoding::Utf16Le => decode_utf16(&bytes[2..], true)?,
        Encoding::Utf16Be => decode_utf16(&bytes[2..], false)?,
    };
    let text = text.replace("\r\n", "\n").replace('\r', "\n");
    Ok((encoding, text))
}

fn decode_utf16(body: &[u8], little_endian: bool) -> Result<String> {
    if !body.len().is_multiple_of(2) {
        return Err(Error::Parse("UTF-16 字幕字节数为奇数".to_string()));
    }
    let units: Vec<u16> = body
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| {
            if little_endian {
                u16::from_le_bytes([pair[0], pair[1]])
            } else {
                u16::from_be_bytes([pair[0], pair[1]])
            }
        })
        .collect();
    String::from_utf16(&units).map_err(|_| Error::Parse("UTF-16 字幕含有非法代理对".to_string()))
}

/// 解一条字幕文件的完整入口：判格式 → 解码 → 解析。
///
/// `hint` 来自扩展名；为 `None` 时按内容嗅探（含 `WEBVTT` 即 VTT，否则 SRT）。
pub fn parse_subtitle(bytes: &[u8], hint: Option<SubtitleFormat>) -> Result<Vec<Cue>> {
    let (_, text) = decode(bytes)?;
    parse_text(&text, hint)
}

/// 解析已解码的文本。
pub fn parse_text(text: &str, hint: Option<SubtitleFormat>) -> Result<Vec<Cue>> {
    let format = hint.unwrap_or_else(|| {
        if text.trim_start().starts_with("WEBVTT") {
            SubtitleFormat::Vtt
        } else {
            SubtitleFormat::Srt
        }
    });
    let cues = match format {
        SubtitleFormat::Srt => parse_srt(text),
        SubtitleFormat::Vtt => parse_vtt(text),
    };
    if cues.is_empty() {
        return Err(Error::Parse("字幕里没有可用的时间轴".to_string()));
    }
    Ok(cues)
}

/// SRT：`序号 / 时间行 / 文本（可多行）/ 空行`，序号可缺。
pub fn parse_srt(text: &str) -> Vec<Cue> {
    let mut cues = Vec::new();
    let mut block: Vec<&str> = Vec::new();
    for line in text.lines().chain(std::iter::once("")) {
        if line.trim().is_empty() {
            if let Some(cue) = srt_block(&block) {
                cues.push(cue);
            }
            block.clear();
            continue;
        }
        block.push(line);
    }
    cues
}

fn srt_block(lines: &[&str]) -> Option<Cue> {
    let timing_index = lines.iter().position(|line| line.contains("-->"))?;
    let (start_ms, end_ms) = parse_timing(lines[timing_index])?;
    let text = cleanup(&lines[timing_index + 1..].join("\n"));
    if text.is_empty() {
        return None;
    }
    Some(Cue {
        start_ms,
        end_ms,
        text,
    })
}

/// VTT：有 `WEBVTT` 头、`NOTE`/`STYLE`/`REGION` 块、时间行后面可带 `align:start` 等设置。
pub fn parse_vtt(text: &str) -> Vec<Cue> {
    let mut cues = Vec::new();
    let mut block: Vec<&str> = Vec::new();
    for line in text.lines().chain(std::iter::once("")) {
        if line.trim().is_empty() {
            if let Some(cue) = vtt_block(&block) {
                cues.push(cue);
            }
            block.clear();
            continue;
        }
        block.push(line);
    }
    cues
}

fn vtt_block(lines: &[&str]) -> Option<Cue> {
    let first = lines.first()?.trim();
    if first.starts_with("WEBVTT")
        || first.starts_with("NOTE")
        || first.starts_with("STYLE")
        || first.starts_with("REGION")
    {
        return None;
    }
    let timing_index = lines.iter().position(|line| line.contains("-->"))?;
    let (start_ms, end_ms) = parse_timing(lines[timing_index])?;
    // 时间行后面可能跟 cue 设置，文本从下一行开始。
    let text = cleanup(&lines[timing_index + 1..].join("\n"));
    if text.is_empty() {
        return None;
    }
    Some(Cue {
        start_ms,
        end_ms,
        text,
    })
}

/// 解析 `00:00:01,000 --> 00:00:04,500`（SRT 用逗号、VTT 用点，两者都收）。
///
/// 时间行尾部允许有 `align:start position:0%` 之类的设置，一律忽略。
fn parse_timing(line: &str) -> Option<(i64, i64)> {
    let (left, right) = line.split_once("-->")?;
    let start = parse_timestamp(left.trim())?;
    // 右侧到第一个空格为止是时间，后面是设置。
    let right = right.trim();
    let end_token = right.split_whitespace().next()?;
    let end = parse_timestamp(end_token)?;
    Some((start, end))
}

/// `HH:MM:SS,mmm` / `MM:SS.mmm` / `SS.mmm` 三种写法。
fn parse_timestamp(token: &str) -> Option<i64> {
    let normalized = token.replace(',', ".");
    let mut parts = normalized.split(':').collect::<Vec<_>>();
    if parts.len() > 3 || parts.is_empty() {
        return None;
    }
    let millis = parse_seconds(parts.pop()?)?;
    let mut total = millis;
    let mut scale = 60_000_i64;
    while let Some(part) = parts.pop() {
        let value: i64 = part.trim().parse().ok()?;
        total += value * scale;
        scale *= 60;
    }
    Some(total)
}

fn parse_seconds(token: &str) -> Option<i64> {
    let (seconds, fraction) = token.split_once('.').unwrap_or((token, ""));
    let seconds: i64 = seconds.trim().parse().ok()?;
    if !(0..60).contains(&seconds) {
        return None;
    }
    let fraction = if fraction.is_empty() {
        0
    } else {
        let digits: String = fraction.chars().take(3).collect();
        let padded = format!("{digits:0<3}");
        padded.parse::<i64>().ok()?
    };
    Some(seconds * 1000 + fraction)
}

/// 去掉标记、合并行。ASS 覆盖标签 `{\an8}` 与 HTML 标签 `<i>` 都不该出现在屏幕上。
fn cleanup(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut in_tag = false;
    let mut in_brace = false;
    for c in raw.chars() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            '{' => in_brace = true,
            '}' if in_brace => in_brace = false,
            '\n' => {
                if !in_tag && !in_brace {
                    out.push('\n');
                }
            }
            _ if in_tag || in_brace => {}
            _ => out.push(c),
        }
    }
    out.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    const SRT: &str = "1\n00:00:01,000 --> 00:00:04,000\n你好\n\n2\n00:00:05,500 --> 00:00:07,250\n<i>第二句</i>\n换行第二行\n";

    #[test]
    fn srt_cues_keep_order_and_text() {
        let cues = parse_srt(SRT);
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0].start_ms, 1_000);
        assert_eq!(cues[0].end_ms, 4_000);
        assert_eq!(cues[0].text, "你好");
        assert_eq!(cues[1].start_ms, 5_500);
        assert_eq!(cues[1].text, "第二句\n换行第二行");
    }

    #[test]
    fn vtt_header_settings_and_notes_are_ignored() {
        let vtt = "WEBVTT\n\nNOTE 这是注释\n不会成为字幕\n\nSTYLE\n::cue { color: red }\n\n00:00:01.000 --> 00:00:02.000 align:start position:0%\n第一句\n\n00:02.000 --> 00:04.500\n第二句\n";
        let cues = parse_vtt(vtt);
        assert_eq!(cues.len(), 2, "{cues:?}");
        assert_eq!(cues[0].text, "第一句");
        assert_eq!(cues[1].start_ms, 2_000);
        assert_eq!(cues[1].end_ms, 4_500);
    }

    #[test]
    fn ass_override_tags_are_dropped_but_breaks_kept() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\n{\\an8}上方字幕\n下一行\n";
        let cues = parse_srt(srt);
        assert_eq!(cues[0].text, "上方字幕\n下一行");
    }

    #[test]
    fn utf16_le_with_bom_is_decoded() {
        let mut bytes = vec![0xFF, 0xFE];
        for unit in "1\n00:00:01,000 --> 00:00:02,000\n你好\n".encode_utf16() {
            bytes.extend_from_slice(&unit.to_le_bytes());
        }
        let (encoding, text) = decode(&bytes).expect("decode");
        assert_eq!(encoding, Encoding::Utf16Le);
        assert!(text.contains("你好"));
        assert_eq!(parse_subtitle(&bytes, None).expect("parse").len(), 1);
    }

    #[test]
    fn utf8_bom_is_stripped_and_content_sniffed() {
        let mut bytes = vec![0xEF, 0xBB, 0xBF];
        bytes.extend_from_slice("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n你好\n".as_bytes());
        let cues = parse_subtitle(&bytes, None).expect("parse");
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].text, "你好");
    }

    #[test]
    fn gbk_without_bom_reports_unsupported_instead_of_garbage() {
        let gbk = [0xC4, 0xE3, 0xBA, 0xC3]; // 「你好」的 GBK 编码
        let error = detect_encoding(&gbk).expect_err("GBK 不该被当成 UTF-8");
        assert_eq!(error.kind(), "unsupported");
        assert!(error.to_string().contains("UTF-8"));
    }

    #[test]
    fn broken_timeline_is_a_parse_error_not_a_panic() {
        assert!(parse_text("1\nnot a timestamp\nhello\n", None).is_err());
        assert!(parse_text("", None).is_err());
        assert!(parse_srt("1\n00:00:00,000 --> \n\n").is_empty());
    }

    #[test]
    fn format_comes_from_the_extension_when_given() {
        // 没有 WEBVTT 头的 VTT 也能按扩展名解析。
        let text = "00:00:01.000 --> 00:00:02.000\nhi\n";
        assert_eq!(
            parse_text(text, Some(SubtitleFormat::Vtt)).unwrap().len(),
            1
        );
        assert_eq!(
            parse_text(text, Some(SubtitleFormat::Srt)).unwrap().len(),
            1
        );
    }

    #[test]
    fn timestamps_accept_hours_and_short_forms() {
        assert_eq!(parse_timestamp("01:02:03,004"), Some(3_723_004));
        assert_eq!(parse_timestamp("02:03.500"), Some(123_500));
        assert_eq!(parse_timestamp("3.25"), Some(3_250));
        assert_eq!(parse_timestamp("bad"), None);
    }
}
