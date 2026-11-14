//! 播放偏好：默认音轨/字幕语言、默认倍速、连播、定时关闭（M3 · T-13）。
//!
//! 只做**数据与校验**，不碰文件、不碰 mpv：落盘走 `Config`/`library`，应用走播放器层。
//!
//! 两条规矩：
//! 1. **坏值回落**，不 panic——偏好文件可能被手改坏，播放器不该因此打不开；
//! 2. **语言匹配不到就说没有**，不悄悄退到第一条轨道——用户以为在看中文字幕，其实在看英文，
//!    比什么都不显示更糟。

use serde::{Deserialize, Serialize};

/// 倍速上下限与可选档位。档位之外的值按最近档位取。
pub const SPEED_STEPS: &[f64] = &[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0, 5.0];

/// 定时关闭。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SleepTimer {
    Off,
    Minutes15,
    Minutes30,
    Minutes60,
    /// 只在「播完当前这一集」时暂停。
    EndOfEpisode,
}

impl SleepTimer {
    /// 距离到点还有多少分钟；`Off` 与「播完本集」返回 `None`。
    pub fn minutes(self) -> Option<i64> {
        match self {
            Self::Off | Self::EndOfEpisode => None,
            Self::Minutes15 => Some(15),
            Self::Minutes30 => Some(30),
            Self::Minutes60 => Some(60),
        }
    }
}

/// 播放偏好（与 `Keymap` 一起构成播放器行为参数）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct PlayerPreferences {
    /// 默认音轨语言：`None` 表示不自动选择（与 ddPlayer 的「不自动选择」一致）。
    pub default_audio_language: Option<String>,
    /// 默认字幕语言；`None` 表示按片源第一条。
    pub default_subtitle_language: Option<String>,
    /// 默认倍速，必须是 `SPEED_STEPS` 之一；非法值回落 1.0。
    pub default_speed: f64,
    /// 连播：播完自动开下一集。
    pub continuous_play: bool,
    /// 续播：开片时回到上次位置。
    pub resume_playback: bool,
    /// 定时关闭。
    pub sleep_timer: SleepTimer,
    /// 快进/快退步长（毫秒），由 `Keymap` 消费；这里存用户选择。
    pub seek_step_ms: i64,
    /// 长按加速倍率。
    pub hold_speed: f64,
}

impl Default for PlayerPreferences {
    fn default() -> Self {
        Self {
            default_audio_language: None,
            default_subtitle_language: Some("zh-Hans".to_string()),
            default_speed: 1.0,
            continuous_play: true,
            resume_playback: true,
            sleep_timer: SleepTimer::Off,
            seek_step_ms: 10_000,
            hold_speed: 2.0,
        }
    }
}

/// 一条可选的轨道（mpv `track-list` 的最小投影）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrackInfo {
    pub id: i64,
    /// BCP-47 或 mpv 给的语言标签，可能为空。
    pub language: Option<String>,
    pub title: Option<String>,
}

impl PlayerPreferences {
    /// 把倍速夹到合法档位：先夹区间，再取最近档位。
    pub fn normalized_speed(value: f64) -> f64 {
        if !value.is_finite() {
            return 1.0;
        }
        let clamped = value.clamp(SPEED_STEPS[0], *SPEED_STEPS.last().unwrap_or(&1.0));
        SPEED_STEPS
            .iter()
            .copied()
            .min_by(|a, b| (a - clamped).abs().total_cmp(&(b - clamped).abs()))
            .unwrap_or(1.0)
    }

    /// 修正整份偏好：坏值回落默认，不报错（与 `Config` 的「坏配置报错」不同，
    /// 因为偏好坏了不该让播放器打不开）。
    pub fn sanitized(mut self) -> Self {
        let defaults = Self::default();
        self.default_speed = Self::normalized_speed(self.default_speed);
        if !(1_000..=120_000).contains(&self.seek_step_ms) {
            self.seek_step_ms = defaults.seek_step_ms;
        }
        if !(1.0..=8.0).contains(&self.hold_speed) || !self.hold_speed.is_finite() {
            self.hold_speed = defaults.hold_speed;
        }
        self.default_subtitle_language = normalize_language(self.default_subtitle_language);
        self.default_audio_language = normalize_language(self.default_audio_language);
        self
    }

    /// 从轨道列表里挑出默认字幕；**匹配不到返回 `None`**，由 UI 明确提示「本集无简体中文字幕」。
    pub fn pick_subtitle<'a>(&self, tracks: &'a [TrackInfo]) -> Option<&'a TrackInfo> {
        pick_track(tracks, self.default_subtitle_language.as_deref())
    }

    /// 从轨道列表里挑出默认音轨；`None` 表示「不自动选择」，保持片源默认。
    pub fn pick_audio<'a>(&self, tracks: &'a [TrackInfo]) -> Option<&'a TrackInfo> {
        pick_track(tracks, self.default_audio_language.as_deref())
    }
}

/// 语言标签归一化：`zh_Hans` / `ZH-hans` → `zh-Hans`；空串当 `None`。
fn normalize_language(value: Option<String>) -> Option<String> {
    let value = value?;
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let mut parts = trimmed.split(['-', '_']);
    let primary = parts.next().unwrap_or("").to_lowercase();
    match parts.next() {
        Some(script) if !script.is_empty() => {
            let mut script_chars = script.chars();
            let head = script_chars
                .next()
                .map(|c| c.to_ascii_uppercase())
                .unwrap_or_default();
            let tail: String = script_chars.as_str().to_lowercase();
            Some(format!("{primary}-{head}{tail}"))
        }
        _ => Some(primary),
    }
}

/// 语言匹配顺序：全等 → 同前缀（`zh-Hant` 配 `zh-Hant-HK`）→ 同 script
/// （`zh-Hant` 优先配另一条繁体，而不是简体）→ 同主语言 → 标题别名兜底。
///
/// 都不匹配返回 `None`：**绝不退回第一条轨道**。
fn pick_track<'a>(tracks: &'a [TrackInfo], wanted: Option<&str>) -> Option<&'a TrackInfo> {
    let wanted = wanted?;
    let wanted_lower = wanted.to_lowercase();
    let wanted_primary = wanted_lower.split('-').next().unwrap_or("").to_string();
    let wanted_script = wanted_lower
        .split_once('-')
        .map(|(_, script)| script.to_string());

    let tag = |track: &'a TrackInfo| track.language.as_deref().map(str::to_lowercase);

    // 1. 完全一致。
    if let Some(found) = tracks
        .iter()
        .find(|track| tag(track).is_some_and(|value| value == wanted_lower))
    {
        return Some(found);
    }

    // 2. 同一标签的前缀扩展（zh-hant → zh-hant-hk）。
    if let Some(found) = tracks.iter().find(|track| {
        tag(track).is_some_and(|value| value.starts_with(&format!("{wanted_lower}-")))
    }) {
        return Some(found);
    }

    // 3. 同 script：要繁体就给另一条繁体，别拿简体凑数。
    if let Some(script) = wanted_script.as_deref()
        && let Some(found) = tracks
            .iter()
            .find(|track| tag(track).is_some_and(|value| value.split('-').nth(1) == Some(script)))
    {
        return Some(found);
    }

    // 4. 同主语言（zh-Hans 能落到 zh 上，反之亦然）。
    if let Some(found) = tracks.iter().find(|track| {
        tag(track).is_some_and(|value| value.split('-').next() == Some(wanted_primary.as_str()))
    }) {
        return Some(found);
    }

    // 5. 语言标签缺失时用标题兜底。
    tracks.iter().find(|track| {
        let Some(title) = track.title.as_deref() else {
            return false;
        };
        let lower = title.to_lowercase();
        lower.contains(&wanted_lower)
            || language_alias(&wanted_primary)
                .iter()
                .any(|alias| lower.contains(alias))
    })
}

/// 主语言的中英文别名，用于标题兜底匹配。
fn language_alias(primary: &str) -> &'static [&'static str] {
    match primary {
        "zh" => &["中文", "简体", "繁体", "chinese", "chs", "cht"],
        "en" => &["英文", "英语", "english"],
        "ja" => &["日文", "日语", "japanese"],
        "ko" => &["韩文", "韩语", "korean"],
        _ => &[],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track(id: i64, language: Option<&str>, title: Option<&str>) -> TrackInfo {
        TrackInfo {
            id,
            language: language.map(str::to_string),
            title: title.map(str::to_string),
        }
    }

    #[test]
    fn defaults_are_the_ones_we_argued_for() {
        let prefs = PlayerPreferences::default();
        assert_eq!(prefs.default_speed, 1.0);
        assert_eq!(prefs.default_subtitle_language.as_deref(), Some("zh-Hans"));
        assert_eq!(prefs.default_audio_language, None, "音轨默认不自动选择");
        assert!(prefs.continuous_play);
        assert_eq!(prefs.sleep_timer, SleepTimer::Off);
        assert_eq!(prefs.seek_step_ms, 10_000);
    }

    #[test]
    fn speed_snaps_to_the_nearest_allowed_step() {
        assert_eq!(PlayerPreferences::normalized_speed(1.1), 1.0);
        assert_eq!(PlayerPreferences::normalized_speed(1.3), 1.25);
        assert_eq!(PlayerPreferences::normalized_speed(9.0), 5.0);
        assert_eq!(PlayerPreferences::normalized_speed(f64::NAN), 1.0);
    }

    #[test]
    fn bad_values_fall_back_instead_of_panicking() {
        let prefs = PlayerPreferences {
            default_speed: 1.2,
            seek_step_ms: 7,
            hold_speed: 99.0,
            ..PlayerPreferences::default()
        }
        .sanitized();
        assert_eq!(prefs.default_speed, 1.25);
        assert_eq!(prefs.seek_step_ms, 10_000);
        assert_eq!(prefs.hold_speed, 2.0);
    }

    #[test]
    fn language_tags_are_normalised() {
        assert_eq!(
            normalize_language(Some("zh_Hans".into())).as_deref(),
            Some("zh-Hans")
        );
        assert_eq!(
            normalize_language(Some("ZH-hans".into())).as_deref(),
            Some("zh-Hans")
        );
        assert_eq!(normalize_language(Some("  ".into())), None);
        assert_eq!(normalize_language(Some("EN".into())).as_deref(), Some("en"));
    }

    #[test]
    fn subtitle_pick_prefers_exact_then_primary_language() {
        let tracks = vec![
            track(1, Some("en"), Some("English")),
            track(2, Some("zh-Hans"), Some("简体中文")),
            track(3, Some("zh-Hant"), Some("繁體中文")),
        ];
        let prefs = PlayerPreferences::default();
        assert_eq!(prefs.pick_subtitle(&tracks).map(|t| t.id), Some(2));

        let cantonese = PlayerPreferences {
            default_subtitle_language: Some("zh-Hant".into()),
            ..PlayerPreferences::default()
        };
        assert_eq!(cantonese.pick_subtitle(&tracks).map(|t| t.id), Some(3));

        // 只要主语言：zh 命中第一条中文轨。
        let any_chinese = PlayerPreferences {
            default_subtitle_language: Some("zh".into()),
            ..PlayerPreferences::default()
        };
        assert_eq!(any_chinese.pick_subtitle(&tracks).map(|t| t.id), Some(2));
    }

    #[test]
    fn missing_language_reports_none_instead_of_the_first_track() {
        let tracks = vec![track(1, Some("en"), None), track(2, None, Some("Japanese"))];
        let prefs = PlayerPreferences::default();
        assert!(
            prefs.pick_subtitle(&tracks).is_none(),
            "没有中文字幕就该说没有"
        );

        let no_preference = PlayerPreferences {
            default_subtitle_language: None,
            ..PlayerPreferences::default()
        };
        assert!(no_preference.pick_subtitle(&tracks).is_none());
    }

    #[test]
    fn title_is_used_when_language_tag_is_missing() {
        let tracks = vec![
            track(7, None, Some("简体中文 (SRT)")),
            track(8, None, Some("English")),
        ];
        let prefs = PlayerPreferences::default();
        assert_eq!(prefs.pick_subtitle(&tracks).map(|t| t.id), Some(7));
    }

    #[test]
    fn audio_preference_absent_means_keep_the_source_default() {
        let tracks = vec![track(1, Some("ja"), None), track(2, Some("zh"), None)];
        let prefs = PlayerPreferences::default();
        assert!(prefs.pick_audio(&tracks).is_none());

        let prefer_zh = PlayerPreferences {
            default_audio_language: Some("zh".into()),
            ..PlayerPreferences::default()
        };
        assert_eq!(prefer_zh.pick_audio(&tracks).map(|t| t.id), Some(2));
    }

    #[test]
    fn sleep_timer_minutes_are_explicit() {
        assert_eq!(SleepTimer::Off.minutes(), None);
        assert_eq!(SleepTimer::EndOfEpisode.minutes(), None);
        assert_eq!(SleepTimer::Minutes30.minutes(), Some(30));
    }

    #[test]
    fn preferences_round_trip_through_json() {
        let prefs = PlayerPreferences::default();
        let json = serde_json::to_string(&prefs).expect("serialize");
        let back: PlayerPreferences = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back, prefs);
        // 缺字段的旧文件也能读（serde default）。
        let partial: PlayerPreferences =
            serde_json::from_str(r#"{"default_speed":1.5}"#).expect("partial");
        assert_eq!(partial.default_speed, 1.5);
        assert!(partial.continuous_play);
    }
}
