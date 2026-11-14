//! 宿主窗口（mpv 自持的 `NSWindow`）：定位、只读探针、全屏、框架同步。
//!
//! 为什么按标题找：mpv 的 cocoa-cb 自己建窗口，我们拿不到它的指针；
//! `title=SeeWow Player` 是唯一稳定的定位键（HLD §5.1 / §9.2）。
//!
//! 平台的扩展点（`NativeWindow` trait）留到扩 Windows/Linux 时再抽（HLD §10）；
//! M1 保持具体实现，不为了「将来」写空 trait。

use objc2::MainThreadMarker;
use objc2::rc::Retained;
use objc2::runtime::{AnyClass, AnyObject};
use objc2::{msg_send, sel};
use objc2_app_kit::{NSApplication, NSWindow};
use objc2_foundation::{NSArray, NSRect};

use crate::probe::{LayerState, ScreenState};

/// 屏幕坐标下的矩形（AppKit base 坐标：原点在左下）。
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Frame {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

impl Frame {
    /// 半像素以内算没变（AppKit 会把逻辑尺寸取整，别为 0.2px 每帧重设窗口）。
    pub fn approx_eq(&self, other: &Frame) -> bool {
        (self.x - other.x).abs() < 0.5
            && (self.y - other.y).abs() < 0.5
            && (self.w - other.w).abs() < 0.5
            && (self.h - other.h).abs() < 0.5
    }
}

impl std::fmt::Display for Frame {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{{{:.0},{:.0} {:.0}x{:.0}}}",
            self.x, self.y, self.w, self.h
        )
    }
}

/// 候选窗口的纯数据描述（不碰 AppKit，便于单测）。
#[derive(Clone, Debug, PartialEq)]
pub struct CandidateWindow {
    pub title: String,
    pub class: String,
    pub miniaturized: bool,
}

/// 从候选里挑出 mpv 的宿主窗口。
///
/// 定位键**必须与标题无关**：mpv 在 `loadfile` 之后会把窗口标题改成媒体名，
/// 用 `title == "SeeWow Player"` 定位会在真在播的那两次失败（E4004）。
/// 判据：class 是 mpv 的 AppKit 窗口类（`swift.Window`），且不是我们自己的 winit 窗口、未被最小化。
pub fn pick_host_window(candidates: &[CandidateWindow]) -> Option<usize> {
    // 主判据：类名。mpv 0.42 的 macOS 窗口类是 `swift.Window`；
    // 我们自己的 Slint 窗口是 `WinitWindow`，任何情况下都不许选中。
    let by_class = candidates
        .iter()
        .position(|candidate| !candidate.miniaturized && is_mpv_window_class(&candidate.class));
    if by_class.is_some() {
        return by_class;
    }
    // 退路：老版本 mpv 可能仍是普通 NSWindow，用标题兜底（仍然排除 winit 与最小化）
    candidates.iter().position(|candidate| {
        !candidate.miniaturized
            && !is_our_own_window_class(&candidate.class)
            && candidate.title == HOST_TITLE_FALLBACK
    })
}

fn is_mpv_window_class(class: &str) -> bool {
    // `swift.Window`（mpv 0.42）；其它 mpv 自建窗口也常以 .Window 结尾
    class == "swift.Window" || (class.ends_with(".Window") && !is_our_own_window_class(class))
}

fn is_our_own_window_class(class: &str) -> bool {
    class == "WinitWindow" || class.contains("Winit")
}

/// 按类名在 `NSApp.windows` 里找 mpv 的宿主窗口（标题仅用于日志：mpv 会在 loadfile 后改标题）。
pub fn find_host_window() -> Option<Retained<NSWindow>> {
    let mtm = main_thread()?;
    let app = NSApplication::sharedApplication(mtm);
    let windows: Retained<NSArray<NSWindow>> = app.windows();
    let mut candidates = Vec::new();
    let mut raw = Vec::new();
    for index in 0..windows.count() {
        let window = windows.objectAtIndex(index);
        candidates.push(CandidateWindow {
            title: window.title().to_string(),
            class: class_name(&window),
            miniaturized: window.isMiniaturized(),
        });
        raw.push(window);
    }
    pick_host_window(&candidates).map(|index| raw[index].clone())
}

const HOST_TITLE_FALLBACK: &str = "SeeWow Player";

/// 扫描失败时的窗口清单（含可见性与最小化，供一行诊断）。
#[derive(Clone, Debug, PartialEq)]
pub struct WindowDetail {
    pub title: String,
    pub class: String,
    pub visible: bool,
    pub miniaturized: bool,
}

/// 扫描失败诊断行：一行打完「锁屏状态 + 每个窗口的 title/class/可见性/最小化」。
///
/// 定位失败时**必须能自证**（评审要求）：不是静默重试，也不是猜「大概是锁屏」。
pub fn windows_diagnostic_line(windows: &[WindowDetail], locked: Option<bool>) -> String {
    let lock_text = match locked {
        Some(true) => "locked=true",
        Some(false) => "locked=false",
        None => "locked=unknown",
    };
    let mut line = format!("window-diag: {lock_text} | {} 个窗口", windows.len());
    for window in windows {
        line.push_str(&format!(
            " | title={:?} class={} visible={} mini={}",
            window.title, window.class, window.visible, window.miniaturized
        ));
    }
    line
}

/// 当前会话是否锁屏（`CGSessionCopyCurrentDictionary` 的 `CGSSessionScreenIsLocked`）。
/// 读不到时返回 `None`（写日志时显示 unknown，不猜）。
pub fn screen_locked() -> Option<bool> {
    use objc2::rc::Retained;
    use objc2::runtime::AnyObject;
    use objc2_foundation::{NSNumber, NSString};

    #[link(name = "ApplicationServices", kind = "framework")]
    unsafe extern "C" {
        fn CGSessionCopyCurrentDictionary() -> *const core::ffi::c_void;
    }

    unsafe {
        let dict = CGSessionCopyCurrentDictionary();
        if dict.is_null() {
            return None;
        }
        let dict: &AnyObject = &*(dict as *const AnyObject);
        let key = NSString::from_str("CGSSessionScreenIsLocked");
        let value: *mut AnyObject = objc2::msg_send![dict, objectForKey: &*key];
        if value.is_null() {
            return Some(false);
        }
        let value: Retained<AnyObject> = Retained::retain(value)?;
        let number = value.downcast::<NSNumber>().ok()?;
        Some(number.boolValue())
    }
}

/// 全表（含可见性与最小化），供诊断行使用。
pub fn list_detailed() -> Vec<WindowDetail> {
    let Some(mtm) = main_thread() else {
        return Vec::new();
    };
    let app = NSApplication::sharedApplication(mtm);
    let windows: Retained<NSArray<NSWindow>> = app.windows();
    let mut out = Vec::new();
    for index in 0..windows.count() {
        let window = windows.objectAtIndex(index);
        out.push(WindowDetail {
            title: window.title().to_string(),
            class: class_name(&window),
            visible: window.isVisible(),
            miniaturized: window.isMiniaturized(),
        });
    }
    out
}

/// 一个窗口的自我介绍（V1 验证项：打印候选项的 title / class）。
#[derive(Clone, Debug, PartialEq)]
pub struct WindowInfo {
    pub title: String,
    pub class: String,
    pub number: isize,
    pub frame: Frame,
}

pub fn main_thread() -> Option<MainThreadMarker> {
    MainThreadMarker::new()
}

/// 按标题在 `NSApp.windows` 里找窗口（**不阻塞**，调用者自己决定重试节奏）。
pub fn find_by_title(title: &str) -> Option<Retained<NSWindow>> {
    let app = NSApplication::sharedApplication(main_thread()?);
    let windows: Retained<NSArray<NSWindow>> = app.windows();
    // 用 Rust 字符串比较而不是 `isEqualToString:`：后者在 Swift 桥接的
    // __StringStorage 上返回编码与 BOOL 不一致（实测 panic：'c' vs 'B'）。
    for index in 0..windows.count() {
        let window = windows.objectAtIndex(index);
        if window.title().to_string() == title {
            return Some(window);
        }
    }
    None
}

/// 列出当前所有窗口（定位日志与 V1 证据用）。
pub fn list() -> Vec<WindowInfo> {
    let Some(_mtm) = main_thread() else {
        return Vec::new();
    };
    let app = NSApplication::sharedApplication(_mtm);
    let windows: Retained<NSArray<NSWindow>> = app.windows();
    let mut out = Vec::new();
    for index in 0..windows.count() {
        let window = windows.objectAtIndex(index);
        out.push(WindowInfo {
            title: window.title().to_string(),
            class: class_name(&window),
            number: window.windowNumber(),
            frame: frame(&window),
        });
    }
    out
}

pub fn class_name(window: &NSWindow) -> String {
    let cls: *const AnyClass = unsafe { msg_send![window, class] };
    if cls.is_null() {
        return "n/a".to_string();
    }
    unsafe { (*cls).name().to_string_lossy().into_owned() }
}

pub fn title(window: &NSWindow) -> String {
    window.title().to_string()
}

pub fn frame(window: &NSWindow) -> Frame {
    let rect: NSRect = window.frame();
    Frame {
        x: rect.origin.x,
        y: rect.origin.y,
        w: rect.size.width,
        h: rect.size.height,
    }
}

pub fn set_frame(window: &NSWindow, frame: Frame) {
    let rect = NSRect::new(
        objc2_foundation::NSPoint::new(frame.x, frame.y),
        objc2_foundation::NSSize::new(frame.w, frame.h),
    );
    window.setFrame_display(rect, true);
}

pub fn set_accepts_mouse_moved(window: &NSWindow, accepts: bool) {
    window.setAcceptsMouseMovedEvents(accepts);
}

pub fn set_ignores_mouse(window: &NSWindow, ignores: bool) {
    window.setIgnoresMouseEvents(ignores);
}

pub fn order_out(window: &NSWindow) {
    window.orderOut(None);
}

pub fn miniaturize(window: &NSWindow) {
    window.miniaturize(None);
}

pub fn is_visible(window: &NSWindow) -> bool {
    window.isVisible()
}

pub fn is_fullscreen(window: &NSWindow) -> bool {
    window
        .styleMask()
        .contains(objc2_app_kit::NSWindowStyleMask::FullScreen)
}

pub fn toggle_fullscreen(window: &NSWindow) {
    window.toggleFullScreen(None);
}

/// 屏幕 EDR 能力 + 名字 + scaling（B 组，只读；本机 SDR 屏 headroom = 1.0 是预期）。
pub fn screen_edr(window: &NSWindow) -> ScreenState {
    let Some(screen) = window.screen() else {
        return ScreenState::default();
    };
    ScreenState {
        max_potential_edr: screen.maximumPotentialExtendedDynamicRangeColorComponentValue(),
        max_current_edr: screen.maximumExtendedDynamicRangeColorComponentValue(),
        name: screen.localizedName().to_string(),
        scale: screen.backingScaleFactor(),
    }
}

/// 没有宿主窗口时也能读到屏幕 EDR（主屏）。
pub fn screen_edr_main() -> ScreenState {
    let Some(_mtm) = main_thread() else {
        return ScreenState::default();
    };
    let Some(screen) = objc2_app_kit::NSScreen::mainScreen(_mtm) else {
        return ScreenState::default();
    };
    ScreenState {
        max_potential_edr: screen.maximumPotentialExtendedDynamicRangeColorComponentValue(),
        max_current_edr: screen.maximumExtendedDynamicRangeColorComponentValue(),
        name: screen.localizedName().to_string(),
        scale: screen.backingScaleFactor(),
    }
}

/// 视频窗口图层（CAMetalLayer）的三个只读属性。
///
/// `colorspace` 由调用方传入 —— M1 用 mpv 的 `options/cocoa-cb-output-csp` 读回值代表
/// 图层色彩空间；直接读 `CGColorSpace` 名字要引 `objc2-core-graphics`，留给 T-24。
///
/// 这里用 `msg_send` 而不是 `NSView::layer()`：后者的返回类型来自 `objc2-quartz-core`，
/// 只为读三个属性不值得再引一个 crate（HLD §3.4 的依赖冻结）。
pub fn layer_state(window: &NSWindow, colorspace: &str) -> LayerState {
    let mut state = LayerState {
        colorspace: colorspace.to_string(),
        ..Default::default()
    };
    let Some(view) = window.contentView() else {
        return state;
    };
    let layer: *mut AnyObject = unsafe { msg_send![&*view, layer] };
    if layer.is_null() {
        return state;
    }
    // 真实图层可能不是 contentView 的直接 layer（mpv 的 Swift 后端会挂子图层），
    // 所以向下找最多 4 层，取第一个响应 pixelFormat 的 CAMetalLayer。
    let mut candidates: Vec<*mut AnyObject> = vec![layer];
    unsafe {
        let sublayers_sel = sel!(sublayers);
        let mut index = 0;
        while index < candidates.len() && candidates.len() < 32 {
            let current = candidates[index];
            index += 1;
            let responds: bool = msg_send![current, respondsToSelector: sublayers_sel];
            if !responds {
                continue;
            }
            let sublayers: *mut AnyObject = msg_send![current, sublayers];
            if sublayers.is_null() {
                continue;
            }
            let count: usize = msg_send![sublayers, count];
            for item in 0..count {
                let child: *mut AnyObject = msg_send![sublayers, objectAtIndex: item];
                if !child.is_null() {
                    candidates.push(child);
                }
            }
        }
    }

    unsafe {
        let wants_edr_sel = sel!(wantsExtendedDynamicRangeContent);
        let responds_edr: bool = msg_send![layer, respondsToSelector: wants_edr_sel];
        if responds_edr {
            let wants: bool = msg_send![layer, wantsExtendedDynamicRangeContent];
            state.wants_edr = wants;
        }

        let pixel_format_sel = sel!(pixelFormat);
        for candidate in &candidates {
            let responds_pf: bool = msg_send![*candidate, respondsToSelector: pixel_format_sel];
            if responds_pf {
                let pixel_format: u64 = msg_send![*candidate, pixelFormat];
                let name = metal_format_name(pixel_format);
                // 8bit 的中间图层不算目标层，继续找；找不到就把最后看到的记下来
                if name != "mtl#0" {
                    state.pixel_format = name;
                    if crate::probe::is_10bit_xr_surface(&state.pixel_format) {
                        break;
                    }
                }
            }
        }
    }
    state
}

/// `MTLPixelFormat` 数值 → 可读名字（只列 M1 会遇到的几个）。
pub fn metal_format_name(format: u64) -> String {
    // 数值对照 Metal 头文件的 MTLPixelFormat（评审逐条核对过）
    match format {
        70 => "rgba8unorm".to_string(),
        80 => "bgra8unorm".to_string(),
        81 => "bgra8unorm_srgb".to_string(),
        // RGB10A2Unorm 是 10-bit，但**不是 XR**：不能算进 HDR 表面族
        90 => "rgb10a2unorm".to_string(),
        // 10-bit XR 族（ADR-0010 v3 认这一族；mpv 0.42 在 macOS 实测是 BGR10A2Unorm）
        94 => "bgr10a2unorm".to_string(),
        552 => "bgra10_xr".to_string(),
        553 => "bgra10_xr_srgb".to_string(),
        554 => "bgr10_xr".to_string(),
        555 => "bgr10_xr_srgb".to_string(),
        115 => "rgba16float".to_string(),
        other => format!("mtl#{other}"),
    }
}
#[cfg(test)]
mod tests {
    use super::*;

    fn candidate(title: &str, class: &str, miniaturized: bool) -> CandidateWindow {
        CandidateWindow {
            title: title.to_string(),
            class: class.to_string(),
            miniaturized,
        }
    }

    /// mpv 在 loadfile 后会把标题改成媒体名 —— 仍然必须定位得到。
    #[test]
    fn locates_host_window_after_mpv_renames_title() {
        let list = vec![
            candidate("SeeWow Overlay", "WinitWindow", false),
            candidate("hdr10-sample", "swift.Window", false),
        ];
        assert_eq!(pick_host_window(&list), Some(1));
    }

    /// 自己的 Slint/winit 窗口绝不能被当成宿主。
    #[test]
    fn never_picks_our_own_winit_window() {
        let list = vec![candidate("SeeWow Player", "WinitWindow", false)];
        assert_eq!(pick_host_window(&list), None);
    }

    /// 最小化的宿主窗口不用（拿不到可用 frame）。
    #[test]
    fn skips_miniaturized_host_window() {
        let list = vec![candidate("whatever", "swift.Window", true)];
        assert_eq!(pick_host_window(&list), None);
    }

    /// 空列表不 panic，返回 None。
    #[test]
    fn empty_list_is_none() {
        assert_eq!(pick_host_window(&[]), None);
    }

    /// 扫描失败时必须能自证：全表 + 可见性 + 是否锁屏，一行打完。
    #[test]
    fn scan_failure_line_lists_every_window_with_visibility_and_lock_state() {
        let windows = vec![
            WindowDetail {
                title: "SeeWow Overlay".to_string(),
                class: "WinitWindow".to_string(),
                visible: true,
                miniaturized: false,
            },
            WindowDetail {
                title: "hdr10-sample".to_string(),
                class: "swift.Window".to_string(),
                visible: false,
                miniaturized: true,
            },
        ];
        let line = windows_diagnostic_line(&windows, Some(true));

        assert!(line.contains("locked=true"), "要写明锁屏状态，实际：{line}");
        assert!(line.contains("2 个窗口"), "要写明窗口数，实际：{line}");
        assert!(
            line.contains(r#"title="SeeWow Overlay" class=WinitWindow visible=true mini=false"#),
            "实际：{line}"
        );
        assert!(
            line.contains(r#"title="hdr10-sample" class=swift.Window visible=false mini=true"#),
            "实际：{line}"
        );
    }

    /// 没有窗口时也要出一行（不是静默失败）。
    #[test]
    fn scan_failure_line_handles_empty_list() {
        let line = windows_diagnostic_line(&[], None);
        assert!(line.contains("0 个窗口"), "实际：{line}");
        assert!(line.contains("locked=unknown"), "实际：{line}");
    }

    /// MTLPixelFormat → 名字，喂 raw number（对照 Metal 头文件）。
    #[test]
    fn metal_pixel_format_table_matches_metal_header() {
        assert_eq!(metal_format_name(70), "rgba8unorm");
        assert_eq!(metal_format_name(80), "bgra8unorm");
        assert_eq!(metal_format_name(81), "bgra8unorm_srgb");
        assert_eq!(metal_format_name(90), "rgb10a2unorm");
        assert_eq!(metal_format_name(94), "bgr10a2unorm");
        assert_eq!(metal_format_name(115), "rgba16float");
        assert_eq!(metal_format_name(552), "bgra10_xr");
        assert_eq!(metal_format_name(553), "bgra10_xr_srgb");
        assert_eq!(metal_format_name(554), "bgr10_xr");
        assert_eq!(metal_format_name(555), "bgr10_xr_srgb");
    }

    /// 94/552/115 属于 XR/16F 族，80 与 90 不属于（90 是 RGB10A2Unorm，不是 XR）。
    #[test]
    fn surface_family_judgement_uses_raw_numbers() {
        use crate::probe::is_10bit_xr_surface;
        assert!(is_10bit_xr_surface(&metal_format_name(94)));
        assert!(is_10bit_xr_surface(&metal_format_name(552)));
        assert!(is_10bit_xr_surface(&metal_format_name(115)));
        assert!(!is_10bit_xr_surface(&metal_format_name(80)));
        assert!(!is_10bit_xr_surface(&metal_format_name(90)));
    }
}
