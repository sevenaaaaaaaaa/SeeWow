//! 文件名解析：片名、剧名、季集、年份、画质。
//!
//! 行为基准是 Flutter 主线的 FilenameParser，但有两处**刻意偏差**（规划 D-04）：
//!
//! 1. 画质 token 必须有词边界：Flutter 用无边界正则，会把 "Adventure" 里的 "dv"
//!    认成 Dolby Vision；这里按 token 匹配。
//! 2. 季集与年份的识别按同一套规则，但用扫描实现而不是正则，避免 Rust 正则不支持
//!    后行断言带来的行为差异。
//!
//! 解析结果只描述「文件名里能确定的信息」。拿不准就留空，不猜。

/// 一条文件名解析结果。
#[derive(Debug, Clone, PartialEq)]
pub struct ParsedName {
    /// 展示用标题。剧集是「剧名 SxxEyy」；父目录只在文件本身没有剧名时补全，
    /// 分类文件夹（「电影」「纪录片」）不进入标题（D-07）。
    pub title: String,
    /// 仅在识别到季集时存在。
    pub show_title: Option<String>,
    pub season: Option<u32>,
    pub episode: Option<u32>,
    pub year: Option<i32>,
    /// 「 · 」连接的画质标签，例如 "4K · HDR · BluRay"。
    pub quality: String,
}

/// 解析一个文件名。parent_folder 用于补全剧名（可选）。
pub fn parse_file_name(file_name: &str, parent_folder: Option<&str>) -> ParsedName {
    let normalized = normalize_stem(file_name);
    let chars: Vec<char> = normalized.chars().collect();

    let mut season = None;
    let mut episode = None;
    let mut show = None;

    if let Some((start, s, e)) = find_season_episode(&chars) {
        season = Some(s);
        episode = Some(e);
        show = Some(clean(&chars[..start]));
    }

    // 刻意偏差 D-04：纯 "S01E02.mkv" 且父目录是剧名时，用父目录补剧名。
    // Flutter 在这种情况下会退化成标题 "S01E02"，剧名信息只存在于文件夹里。
    if season.is_some()
        && episode.is_some()
        && show.as_deref().is_none_or(|show| show.is_empty())
        && let Some(folder) = parent_folder
    {
        let folder = clean(&folder.chars().collect::<Vec<char>>());
        // D-07：「怪奇物语 S01」「怪奇物语 第2季」这类文件夹名里的季标记不进剧名。
        let stripped = strip_season_markers(&folder);
        show = Some(if stripped.is_empty() {
            folder
        } else {
            stripped
        });
    }

    let year_match = find_last_year(&chars);
    let year = year_match.map(|(_, value)| value);
    let quality = quality_labels(&normalized);

    let mut title;
    if let Some(show_title) = show.as_deref().filter(|show| !show.is_empty()) {
        // D-07：剧名已经确定了就不再前缀父目录——「纪录片」「电影」这类分类文件夹
        // 不是剧名的一部分，前缀进去只会让整个片库标题变脏。
        title = (*show_title).to_string();
        if let (Some(s), Some(e)) = (season, episode) {
            title = format!("{title} S{s:02}E{e:02}");
        }
    } else {
        title = clean(&chars);
        if let Some((index, _)) = year_match {
            let head = clean(&chars[..index]);
            if !head.is_empty() {
                title = head;
            }
        }
    }

    if title.trim().is_empty() {
        title = file_name.to_string();
    }

    ParsedName {
        title,
        show_title: show.filter(|show| !show.is_empty()),
        season,
        episode,
        year,
        quality: quality.join(" · "),
    }
}

/// 去掉扩展名并把下划线、点变成空格（与 Flutter 一致）。
fn normalize_stem(file_name: &str) -> String {
    let stem = match file_name.rfind('.') {
        Some(dot) if dot > 0 => &file_name[..dot],
        _ => file_name,
    };
    stem.replace(['_', '.'], " ")
}

/// 依次尝试 SxxExx、1x02、第 N 季 第 M 集；返回（季集模式起点、季、集）。
fn find_season_episode(chars: &[char]) -> Option<(usize, u32, u32)> {
    if let Some(found) = find_sxxexx(chars) {
        return Some(found);
    }
    if let Some(found) = find_nxn(chars) {
        return Some(found);
    }
    find_chinese_season_episode(chars)
}

fn find_sxxexx(chars: &[char]) -> Option<(usize, u32, u32)> {
    let mut i = 0;
    while i < chars.len() {
        let marker = chars[i];
        if marker != 's' && marker != 'S' {
            i += 1;
            continue;
        }
        let mut j = i + 1;
        let digits_start = j;
        while j < chars.len() && chars[j].is_ascii_digit() && j - digits_start < 2 {
            j += 1;
        }
        if j == digits_start || j >= chars.len() || (chars[j] != 'e' && chars[j] != 'E') {
            i += 1;
            continue;
        }
        let season_digits: String = chars[digits_start..j].iter().collect();
        let mut k = j + 1;
        let episode_start = k;
        while k < chars.len() && chars[k].is_ascii_digit() && k - episode_start < 3 {
            k += 1;
        }
        if k == episode_start {
            i += 1;
            continue;
        }
        let episode_digits: String = chars[episode_start..k].iter().collect();
        if let (Ok(season), Ok(episode)) = (season_digits.parse(), episode_digits.parse()) {
            return Some((i, season, episode));
        }
        i += 1;
    }
    None
}

/// 1x02：要求左侧是边界、右侧不是数字，避免把 1920x1080 认成季集。
fn find_nxn(chars: &[char]) -> Option<(usize, u32, u32)> {
    for i in 0..chars.len() {
        if chars[i] != 'x' && chars[i] != 'X' {
            continue;
        }
        let mut left = i;
        while left > 0 && chars[left - 1].is_ascii_digit() && i - (left - 1) <= 2 {
            left -= 1;
        }
        let season_len = i - left;
        if season_len == 0 || season_len > 2 {
            continue;
        }
        if left > 0 && chars[left - 1].is_ascii_alphanumeric() {
            continue;
        }
        let mut right = i + 1;
        while right < chars.len() && chars[right].is_ascii_digit() && right - (i + 1) < 3 {
            right += 1;
        }
        let episode_len = right - (i + 1);
        if episode_len == 0 || episode_len > 3 {
            continue;
        }
        if right < chars.len() && chars[right].is_ascii_digit() {
            continue;
        }
        let season_digits: String = chars[left..i].iter().collect();
        let episode_digits: String = chars[i + 1..right].iter().collect();
        if let (Ok(season), Ok(episode)) = (season_digits.parse(), episode_digits.parse()) {
            return Some((left, season, episode));
        }
    }
    None
}

/// 第 2 季 第 5 集：允许数字与关键字之间有空格。
fn find_chinese_season_episode(chars: &[char]) -> Option<(usize, u32, u32)> {
    let mut i = 0;
    while i < chars.len() {
        if chars[i] != '第' {
            i += 1;
            continue;
        }
        let Some((season, after_season)) = digits_after(chars, i + 1) else {
            i += 1;
            continue;
        };
        let mut cursor = after_season;
        while cursor < chars.len() && chars[cursor] == ' ' {
            cursor += 1;
        }
        if cursor >= chars.len() || chars[cursor] != '季' {
            i += 1;
            continue;
        }
        // 季与集之间允许任意文字（如「第2季 全12集」），但只认第一个「第…集」。
        let mut probe = cursor + 1;
        while probe < chars.len() {
            if chars[probe] == '第'
                && let Some((episode, after_episode)) = digits_after(chars, probe + 1)
            {
                let mut end = after_episode;
                while end < chars.len() && chars[end] == ' ' {
                    end += 1;
                }
                if end < chars.len() && chars[end] == '集' {
                    return Some((i, season, episode));
                }
            }
            probe += 1;
        }
        i += 1;
    }
    None
}

/// 从 index 起跳过空格读 1..=3 位数字，返回（数值，数字后的位置）。
fn digits_after(chars: &[char], index: usize) -> Option<(u32, usize)> {
    let mut cursor = index;
    while cursor < chars.len() && chars[cursor] == ' ' {
        cursor += 1;
    }
    let start = cursor;
    while cursor < chars.len() && chars[cursor].is_ascii_digit() && cursor - start < 3 {
        cursor += 1;
    }
    if cursor == start {
        return None;
    }
    let digits: String = chars[start..cursor].iter().collect();
    digits.parse().ok().map(|value| (value, cursor))
}

/// 最后一个独立的 4 位年份（1900..=2099）。返回（字符下标，年份）。
fn find_last_year(chars: &[char]) -> Option<(usize, i32)> {
    let mut found = None;
    let mut i = 0;
    while i < chars.len() {
        if !chars[i].is_ascii_digit() {
            i += 1;
            continue;
        }
        let start = i;
        while i < chars.len() && chars[i].is_ascii_digit() {
            i += 1;
        }
        if i - start == 4 {
            let digits: String = chars[start..i].iter().collect();
            // 紧跟在汉字/假名/谚文后面的四位数字通常是作品名的一部分，
            // 例如「请回答1988」，不能当成年份。
            let glued_to_cjk = start > 0 && is_cjk(chars[start - 1]);
            if !glued_to_cjk
                && let Ok(value) = digits.parse::<i32>()
                && (1900..=2099).contains(&value)
            {
                found = Some((start, value));
            }
        }
    }
    found
}

fn is_cjk(c: char) -> bool {
    matches!(c as u32, 0x3400..=0x4DBF | 0x4E00..=0x9FFF | 0x3040..=0x30FF | 0xAC00..=0xD7AF | 0xF900..=0xFAFF)
}

fn is_token_char(c: char) -> bool {
    c.is_alphanumeric() || c == '-' || c == '+'
}

fn push_label(labels: &mut Vec<&'static str>, label: &'static str) {
    if !labels.contains(&label) {
        labels.push(label);
    }
}

fn classify_token(token: &str, previous: &str, labels: &mut Vec<&'static str>) {
    let lower = token.to_lowercase();
    if lower == "2160p" || lower == "4k" || lower == "uhd" {
        push_label(labels, "4K");
    } else if lower == "1080p" {
        push_label(labels, "1080p");
    } else if lower == "720p" {
        push_label(labels, "720p");
    } else if lower.starts_with("hdr") {
        push_label(labels, "HDR");
    } else if lower == "dv" || lower == "dolbyvision" || (lower == "vision" && previous == "dolby")
    {
        push_label(labels, "Dolby Vision");
    } else if lower.starts_with("blu") {
        push_label(labels, "BluRay");
    } else if lower.starts_with("web") {
        push_label(labels, "WEB");
    } else if lower.starts_with("remux") {
        push_label(labels, "Remux");
    }
}

/// 画质标签，按出现顺序去重。
fn quality_labels(normalized: &str) -> Vec<&'static str> {
    let mut labels: Vec<&'static str> = Vec::new();
    let mut token = String::new();
    let mut previous = String::new();
    for c in normalized.chars() {
        if is_token_char(c) {
            token.push(c);
        } else if !token.is_empty() {
            classify_token(&token, &previous, &mut labels);
            previous = token.to_lowercase();
            token.clear();
        }
    }
    if !token.is_empty() {
        classify_token(&token, &previous, &mut labels);
    }
    labels
}

/// 发布/编码类噪音词，不会进入标题（与 Flutter 的停用词表一致）。
const STOP_WORDS: &[&str] = &[
    "2160p",
    "1080p",
    "720p",
    "576p",
    "480p",
    "4k",
    "uhd",
    "hdr10",
    "hdr10+",
    "dolby",
    "dolbyvision",
    "vision",
    "dv",
    "bluray",
    "blu-ray",
    "web-dl",
    "webdl",
    "webrip",
    "remux",
    "x264",
    "x265",
    "h264",
    "h265",
    "hevc",
    "av1",
    "aac",
    "dts",
    "truehd",
    "atmos",
    "proper",
    "repack",
    "extended",
    "imax",
    "10bit",
    "8bit",
];

fn is_stop_word(token: &str) -> bool {
    let lower = token.to_lowercase();
    STOP_WORDS.contains(&lower.as_str())
}

fn flush_token(token: &mut String, out: &mut String) {
    if token.is_empty() {
        return;
    }
    if is_stop_word(token) {
        // 只给被删掉的噪音留一个分隔，避免前后两个词粘在一起。
        out.push(' ');
    } else {
        out.push_str(token);
    }
    token.clear();
}

/// 去掉剧集文件夹名里的季标记：「怪奇物语 S01」「Dark Season 2」「某剧 第2季」→ 剧名。
fn strip_season_markers(text: &str) -> String {
    let tokens: Vec<&str> = text.split_whitespace().collect();
    let mut kept: Vec<&str> = Vec::new();
    let mut index = 0;
    while index < tokens.len() {
        let token = tokens[index];
        let lower = token.to_lowercase();
        // 「Season 2」「S 2」是两个词：连同后面的数字一起去掉。
        let is_split_marker = lower == "season" || lower == "s";
        let next_is_number = tokens
            .get(index + 1)
            .is_some_and(|next| !next.is_empty() && next.chars().all(|c| c.is_ascii_digit()));
        if is_split_marker && next_is_number {
            index += 2;
            continue;
        }
        if !is_season_token(token) {
            kept.push(token);
        }
        index += 1;
    }
    trim_trailing_chinese_season(&kept.join(" "))
        .trim()
        .to_string()
}

fn is_season_token(token: &str) -> bool {
    let lower = token.to_lowercase();
    let Some(rest) = lower.strip_prefix('s') else {
        return false;
    };
    if !rest.is_empty() && rest.len() <= 2 && rest.chars().all(|c| c.is_ascii_digit()) {
        return true;
    }
    let Some(number) = rest.strip_prefix("eason") else {
        return false;
    };
    let number = number.trim_start_matches([' ', '.', '-', '_']);
    !number.is_empty() && number.chars().all(|c| c.is_ascii_digit())
}

/// 剪掉结尾的「第 N 季」，中文里季标记通常不带空格。
fn trim_trailing_chinese_season(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() < 3 || chars[chars.len() - 1] != '季' {
        return text.to_string();
    }
    let mut index = chars.len() - 2;
    while index > 0 && chars[index].is_ascii_digit() {
        index -= 1;
    }
    if chars[index] == '第' && index + 1 < chars.len() - 1 {
        return chars[..index].iter().collect::<String>().trim().to_string();
    }
    text.to_string()
}

/// 清理标题：括号变空格、去掉停用词、压平空白、剪掉尾部连字符。
///
/// 标点（逗号、顿号、冒号、&、' 等）原样保留：中文片名里的「，」不是分隔符，
/// 丢掉它等于改片名。
fn clean(chars: &[char]) -> String {
    let mut text = String::with_capacity(chars.len());
    for &c in chars {
        if matches!(c, '[' | ']' | '(' | ')' | '{' | '}') {
            text.push(' ');
        } else {
            text.push(c);
        }
    }
    let mut out = String::with_capacity(text.len());
    let mut token = String::new();
    for c in text.chars() {
        if is_token_char(c) {
            token.push(c);
        } else {
            flush_token(&mut token, &mut out);
            out.push(c);
        }
    }
    flush_token(&mut token, &mut out);
    let collapsed = out.split_whitespace().collect::<Vec<_>>().join(" ");
    collapsed
        .trim_end_matches(['-', '–', '—'])
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bare_episode_file_takes_the_show_name_from_its_folder() {
        let parsed = parse_file_name("S01E02.mkv", Some("Dark"));
        assert_eq!(parsed.show_title.as_deref(), Some("Dark"));
        assert_eq!(parsed.title, "Dark S01E02");
    }

    #[test]
    fn parses_sxxexx_with_quality_and_parent() {
        let parsed = parse_file_name("Dark S01E02 1080p WEB-DL x264.mkv", Some("Dark"));
        assert_eq!(parsed.show_title.as_deref(), Some("Dark"));
        assert_eq!(parsed.season, Some(1));
        assert_eq!(parsed.episode, Some(2));
        assert_eq!(parsed.title, "Dark S01E02");
        assert_eq!(parsed.quality, "1080p · WEB");
    }

    #[test]
    fn parses_nxn_and_chinese_season_episode() {
        let nxn = parse_file_name("Severance 1x03 2160p.mkv", None);
        assert_eq!((nxn.season, nxn.episode), (Some(1), Some(3)));
        assert!(nxn.quality.contains("4K"));

        let chinese = parse_file_name("某剧 第2季 第5集.mp4", None);
        assert_eq!((chinese.season, chinese.episode), (Some(2), Some(5)));
        assert_eq!(chinese.show_title.as_deref(), Some("某剧"));
        assert_eq!(chinese.title, "某剧 S02E05");
    }

    #[test]
    fn parses_movie_title_year_and_quality() {
        let parsed = parse_file_name("Dune Part Two (2024) 2160p HDR10 BluRay.mkv", None);
        assert_eq!(parsed.title, "Dune Part Two");
        assert_eq!(parsed.year, Some(2024));
        assert_eq!(parsed.quality, "4K · HDR · BluRay");
    }

    #[test]
    fn resolution_pairs_are_not_episodes() {
        let parsed = parse_file_name("Some Film 1920x1080.mkv", None);
        assert_eq!(parsed.season, None);
        assert_eq!(parsed.episode, None);
    }

    #[test]
    fn word_boundary_keeps_adventure_out_of_dolby_vision() {
        // 刻意偏差 D-04：Flutter 的无边界正则会把这个片名认成 Dolby Vision。
        let parsed = parse_file_name("Adventure 2021 1080p.mkv", None);
        assert!(!parsed.quality.contains("Dolby Vision"));
        assert_eq!(parsed.quality, "1080p");
    }

    #[test]
    fn dolby_vision_and_dv_are_recognised_as_tokens() {
        assert_eq!(
            parse_file_name("Film 2020 DV.mkv", None).quality,
            "Dolby Vision"
        );
        assert_eq!(
            parse_file_name("Film 2020 Dolby Vision.mkv", None).quality,
            "Dolby Vision"
        );
    }

    #[test]
    fn last_year_wins_and_title_is_trimmed_before_it() {
        let parsed = parse_file_name("Blade Runner 2049 2017 1080p.mkv", None);
        assert_eq!(parsed.year, Some(2017));
        assert_eq!(parsed.title, "Blade Runner 2049");
    }

    #[test]
    fn parent_folder_only_fills_a_missing_show_name() {
        // 文件本身没有剧名（纯 S01E02）→ 用文件夹补。
        let with_folder = parse_file_name("S01E02.mkv", Some("Dark"));
        assert_eq!(with_folder.title, "Dark S01E02");

        // 文件本身有剧名 → 不再前缀文件夹，避免重复。
        let same_name = parse_file_name("Dark S01E02.mkv", Some("Dark"));
        assert_eq!(same_name.title, "Dark S01E02");
    }

    #[test]
    fn category_folder_never_enters_the_title() {
        // D-07：真实片库里「纪录片/蓝色星球 第2季 第1集.mp4」不应变成「纪录片 蓝色星球 …」。
        let parsed = parse_file_name("蓝色星球 第2季 第1集.mp4", Some("纪录片"));
        assert_eq!(parsed.show_title.as_deref(), Some("蓝色星球"));
        assert_eq!(parsed.title, "蓝色星球 S02E01");
    }

    #[test]
    fn season_marker_in_the_folder_never_enters_the_show_name() {
        // D-07：文件夹叫「怪奇物语 S01」时，剧名是「怪奇物语」，不是「怪奇物语 S01」。
        let parsed = parse_file_name("S01E03.mkv", Some("怪奇物语 S01"));
        assert_eq!(parsed.show_title.as_deref(), Some("怪奇物语"));
        assert_eq!(parsed.title, "怪奇物语 S01E03");

        let chinese = parse_file_name("S02E01.mkv", Some("某剧 第2季"));
        assert_eq!(chinese.show_title.as_deref(), Some("某剧"));

        let english = parse_file_name("S02E01.mkv", Some("Dark Season 2"));
        assert_eq!(english.show_title.as_deref(), Some("Dark"));
    }

    #[test]
    fn a_four_digit_year_glued_to_chinese_is_part_of_the_title() {
        let parsed = parse_file_name("请回答1988 第1季 第7集.mkv", None);
        assert_eq!(parsed.year, None, "请回答1988 不是 1988 年的剧");
        assert_eq!(parsed.show_title.as_deref(), Some("请回答1988"));
        assert_eq!((parsed.season, parsed.episode), (Some(1), Some(7)));
    }

    #[test]
    fn chinese_punctuation_stays_in_the_title() {
        let parsed = parse_file_name("你好，李焕英 (2021) 1080p.mkv", None);
        assert_eq!(parsed.title, "你好，李焕英");
        assert_eq!(parsed.year, Some(2021));
    }

    #[test]
    fn empty_and_odd_names_do_not_panic() {
        assert_eq!(parse_file_name("", None).title, "");
        assert_eq!(parse_file_name("no-extension", None).title, "no-extension");
        let dotted = parse_file_name(".hidden", None);
        assert!(!dotted.title.is_empty());
    }

    #[test]
    fn stop_words_do_not_leak_into_titles() {
        let parsed = parse_file_name("Interstellar 2014 IMAX x265 10bit AAC.mkv", None);
        assert_eq!(parsed.title, "Interstellar");
        assert_eq!(parsed.year, Some(2014));
    }
}
