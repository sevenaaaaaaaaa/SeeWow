//! 画面区手势判定（M3 · T-14）。
//!
//! 纯函数：坐标、点击次数、按住时长 → 动作。不碰 AppKit、不碰 mpv，便于单测。
//!
//! 键位与手势的分工：键盘走 `core/keymap.rs`，这里只管鼠标/触摸。
//! 两条规矩：
//! 1. **双击分三区**：左三分之一后退、右三分之一前进、中间全屏（Infuse / VLC 的通用约定）；
//! 2. **按住超过阈值算加速**，松手必须回 1.0x —— 判定不能依赖「松手时补做」，否则用户
//!    按住的 2 秒里画面还是正常速度。

use std::time::Duration;

/// 双击分区的边界比例：左右各 30%，中间 40% 归全屏。
pub const EDGE_RATIO: f32 = 0.30;

/// 按住多久算「长按加速」。
pub const HOLD_TO_START: Duration = Duration::from_millis(350);

/// 按下后位移超过这么多像素就当拖拽，不识别为点击或长按。
pub const MOVE_TOLERANCE: f32 = 6.0;

/// 画面区一次交互的结论。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PictureGesture {
    /// 单击：播放/暂停。
    TogglePause,
    /// 双击左区：后退一个步长。
    SeekBackward,
    /// 双击右区：前进一个步长。
    SeekForward,
    /// 双击中间：全屏切换。
    ToggleFullscreen,
    /// 按住够久：进入临时加速。
    SpeedBoostStart,
    /// 松手：结束临时加速，回到原倍速。
    SpeedBoostEnd,
    /// 拖拽或无效：交给上层忽略。
    Ignore,
}

/// 双击落在哪个区。宽度为 0（还没布局）时一律当中间，避免把点击判到边缘。
pub fn zone_at(x: f32, width: f32) -> PictureGesture {
    if width <= 0.0 {
        return PictureGesture::ToggleFullscreen;
    }
    if x < width * EDGE_RATIO {
        PictureGesture::SeekBackward
    } else if x > width * (1.0 - EDGE_RATIO) {
        PictureGesture::SeekForward
    } else {
        PictureGesture::ToggleFullscreen
    }
}

/// 判断一次「按下 → 松开」是什么手势。
///
/// - `click_count`：AppKit 给的连击计数（≥2 即双击）；
/// - `held`：按住时长；
/// - `moved`：按下到松开的位移（像素）。
pub fn classify(
    click_count: usize,
    x: f32,
    width: f32,
    held: Duration,
    moved: f32,
) -> PictureGesture {
    if moved > MOVE_TOLERANCE {
        return PictureGesture::Ignore;
    }
    if held >= HOLD_TO_START {
        // 长按：按下时已经进加速，松手时结束。
        return PictureGesture::SpeedBoostEnd;
    }
    if click_count >= 2 {
        return zone_at(x, width);
    }
    PictureGesture::TogglePause
}

/// 按住过程中是否该进入加速（由计时器在 `HOLD_TO_START` 后调一次）。
pub fn should_boost(held: Duration, moved: f32) -> bool {
    held >= HOLD_TO_START && moved <= MOVE_TOLERANCE
}

#[cfg(test)]
mod tests {
    use super::*;

    const W: f32 = 1200.0;

    #[test]
    fn single_click_toggles_pause() {
        assert_eq!(
            classify(1, 600.0, W, Duration::from_millis(80), 1.0),
            PictureGesture::TogglePause
        );
    }

    #[test]
    fn double_click_edges_seek_and_middle_toggles_fullscreen() {
        assert_eq!(
            classify(2, 100.0, W, Duration::from_millis(80), 0.0),
            PictureGesture::SeekBackward
        );
        assert_eq!(
            classify(2, 1100.0, W, Duration::from_millis(80), 0.0),
            PictureGesture::SeekForward
        );
        assert_eq!(
            classify(2, 600.0, W, Duration::from_millis(80), 0.0),
            PictureGesture::ToggleFullscreen
        );
    }

    #[test]
    fn zone_boundaries_are_exact() {
        // 30% 处属于左区（< 边界），30.1% 属于中间。
        assert_eq!(zone_at(W * 0.29, W), PictureGesture::SeekBackward);
        assert_eq!(zone_at(W * 0.31, W), PictureGesture::ToggleFullscreen);
        assert_eq!(zone_at(W * 0.70, W), PictureGesture::ToggleFullscreen);
        assert_eq!(zone_at(W * 0.72, W), PictureGesture::SeekForward);
    }

    #[test]
    fn zero_width_falls_back_to_fullscreen() {
        assert_eq!(zone_at(0.0, 0.0), PictureGesture::ToggleFullscreen);
    }

    #[test]
    fn holding_long_enough_ends_the_boost() {
        assert_eq!(
            classify(1, 600.0, W, Duration::from_millis(400), 0.0),
            PictureGesture::SpeedBoostEnd
        );
        assert_eq!(
            classify(1, 600.0, W, Duration::from_millis(349), 0.0),
            PictureGesture::TogglePause
        );
    }

    #[test]
    fn dragging_is_ignored_even_if_it_lasted_long() {
        assert_eq!(
            classify(1, 600.0, W, Duration::from_millis(900), 40.0),
            PictureGesture::Ignore
        );
    }

    #[test]
    fn boost_starts_after_threshold_without_moving() {
        assert!(should_boost(Duration::from_millis(360), 2.0));
        assert!(!should_boost(Duration::from_millis(200), 2.0));
        assert!(!should_boost(Duration::from_millis(900), 30.0));
    }
}
