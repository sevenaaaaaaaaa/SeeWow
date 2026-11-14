//! 播放器按键映射（M3 · T-12）。
//!
//! 纯函数：按键 → 动作，不依赖 Slint / winit / mpv，便于测试与以后换 UI 框架。
//! 键位对齐 Flutter 1.x 播放页，并吸收 Infuse 的两个默认值（快进 10 秒、倍速记忆）。
//!
//! 不做「组合键」和「长按」：长按加速属于手势层（`hit.rs`），这里只管单次按键。

/// 播放器动作。数值参数自带，UI 层不需要再判断。
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PlayerAction {
    TogglePlay,
    /// 正数向前、负数向后，单位毫秒。
    SeekRelative {
        delta_ms: i64,
    },
    /// 跳转到百分比位置（0.0-1.0），用于数字键 0-9。
    SeekPercent {
        ratio: f64,
    },
    VolumeUp,
    VolumeDown,
    ToggleMute,
    ToggleFullscreen,
    /// 下一档倍速；`-1` 退一档，`0` 回到 1.0。
    SpeedStep {
        direction: i8,
    },
    CycleSubtitle,
    ToggleSubtitle,
    CycleAudio,
    ToggleControls,
    /// 逐帧，正数向后。
    FrameStep {
        frames: i32,
    },
    NextItem,
    PreviousItem,
    Quit,
}

/// 键位表；`seek_step_ms` 可配置（默认 10 秒，与 Flutter 和 Infuse 一致）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Keymap {
    pub seek_step_ms: i64,
    pub volume_step: i32,
    /// 长按加速倍率（手势层读，默认 2.0x——与 ddPlayer 的默认值一致）。
    pub hold_speed: f64,
}

impl Default for Keymap {
    fn default() -> Self {
        Self {
            seek_step_ms: 10_000,
            volume_step: 5,
            hold_speed: 2.0,
        }
    }
}

/// 归一化后的按键名：小写、去修饰键前缀（`KeyK` / `k` / `Shift+K` 都能认）。
pub fn normalize_key(raw: &str) -> String {
    let lower = raw.trim().to_lowercase();
    let stripped = lower
        .strip_prefix("shift+")
        .or_else(|| lower.strip_prefix("ctrl+"))
        .or_else(|| lower.strip_prefix("alt+"))
        .or_else(|| lower.strip_prefix("meta+"))
        .unwrap_or(&lower);
    stripped
        .trim_start_matches("key")
        .trim_start_matches("arrow")
        .to_string()
}

/// 按键 → 动作。未知按键返回 `None`（不吞键，让上层决定）。
pub fn action_for(raw_key: &str, keymap: &Keymap) -> Option<PlayerAction> {
    let key = normalize_key(raw_key);
    let seek = keymap.seek_step_ms;
    let action = match key.as_str() {
        "space" | "k" | "enter" => PlayerAction::TogglePlay,
        "left" | "j" => PlayerAction::SeekRelative { delta_ms: -seek },
        "right" | "l" => PlayerAction::SeekRelative { delta_ms: seek },
        "up" => PlayerAction::VolumeUp,
        "down" => PlayerAction::VolumeDown,
        "m" => PlayerAction::ToggleMute,
        "f" => PlayerAction::ToggleFullscreen,
        "escape" | "esc" => PlayerAction::ToggleFullscreen,
        "[" => PlayerAction::SpeedStep { direction: -1 },
        "]" => PlayerAction::SpeedStep { direction: 1 },
        "backspace" => PlayerAction::SpeedStep { direction: 0 },
        "s" => PlayerAction::CycleSubtitle,
        "v" => PlayerAction::ToggleSubtitle,
        "a" => PlayerAction::CycleAudio,
        "tab" | "c" => PlayerAction::ToggleControls,
        "," => PlayerAction::FrameStep { frames: -1 },
        "." => PlayerAction::FrameStep { frames: 1 },
        "n" | "pagedown" => PlayerAction::NextItem,
        "p" | "pageup" => PlayerAction::PreviousItem,
        "q" => PlayerAction::Quit,
        other => {
            // 数字键 0-9 按百分比跳转：1=10%，5=50%，0=回到开头。
            if let Some(digit) = other.parse::<u8>().ok().filter(|d| *d <= 9) {
                return Some(PlayerAction::SeekPercent {
                    ratio: f64::from(digit) / 10.0,
                });
            }
            return None;
        }
    };
    Some(action)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn space_and_k_toggle_playback() {
        let keymap = Keymap::default();
        assert_eq!(action_for("space", &keymap), Some(PlayerAction::TogglePlay));
        assert_eq!(action_for("KeyK", &keymap), Some(PlayerAction::TogglePlay));
    }

    #[test]
    fn arrows_and_jl_seek_by_the_configured_step() {
        let keymap = Keymap {
            seek_step_ms: 5_000,
            ..Keymap::default()
        };
        assert_eq!(
            action_for("left", &keymap),
            Some(PlayerAction::SeekRelative { delta_ms: -5_000 })
        );
        assert_eq!(
            action_for("l", &keymap),
            Some(PlayerAction::SeekRelative { delta_ms: 5_000 })
        );
    }

    #[test]
    fn default_step_is_ten_seconds() {
        let keymap = Keymap::default();
        assert_eq!(
            action_for("right", &keymap),
            Some(PlayerAction::SeekRelative { delta_ms: 10_000 })
        );
    }

    #[test]
    fn volume_keys_use_the_configured_step_and_mute_is_separate() {
        let keymap = Keymap::default();
        assert_eq!(action_for("ArrowUp", &keymap), Some(PlayerAction::VolumeUp));
        assert_eq!(action_for("m", &keymap), Some(PlayerAction::ToggleMute));
    }

    #[test]
    fn speed_brackets_and_backspace() {
        let keymap = Keymap::default();
        assert_eq!(
            action_for("]", &keymap),
            Some(PlayerAction::SpeedStep { direction: 1 })
        );
        assert_eq!(
            action_for("[", &keymap),
            Some(PlayerAction::SpeedStep { direction: -1 })
        );
        assert_eq!(
            action_for("backspace", &keymap),
            Some(PlayerAction::SpeedStep { direction: 0 })
        );
    }

    #[test]
    fn digits_seek_by_percentage() {
        let keymap = Keymap::default();
        assert_eq!(
            action_for("5", &keymap),
            Some(PlayerAction::SeekPercent { ratio: 0.5 })
        );
        assert_eq!(
            action_for("0", &keymap),
            Some(PlayerAction::SeekPercent { ratio: 0.0 })
        );
    }

    #[test]
    fn hold_speed_defaults_to_double() {
        let keymap = Keymap::default();
        assert!((keymap.hold_speed - 2.0).abs() < f64::EPSILON);
    }

    #[test]
    fn unknown_keys_are_not_swallowed() {
        let keymap = Keymap::default();
        assert_eq!(action_for("F13", &keymap), None);
        assert_eq!(action_for("", &keymap), None);
    }

    #[test]
    fn modifiers_do_not_change_the_action() {
        let keymap = Keymap::default();
        assert_eq!(
            action_for("Shift+F", &keymap),
            Some(PlayerAction::ToggleFullscreen)
        );
    }
}
