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
    unsafe {
        let wants_edr_sel = sel!(wantsExtendedDynamicRangeContent);
        let responds_edr: bool = msg_send![layer, respondsToSelector: wants_edr_sel];
        if responds_edr {
            let wants: bool = msg_send![layer, wantsExtendedDynamicRangeContent];
            state.wants_edr = wants;
        }

        let pixel_format_sel = sel!(pixelFormat);
        let responds_pf: bool = msg_send![layer, respondsToSelector: pixel_format_sel];
        if responds_pf {
            let pixel_format: u64 = msg_send![layer, pixelFormat];
            state.pixel_format = metal_pixel_format_name(pixel_format);
        }
    }
    state
}

/// `MTLPixelFormat` 数值 → 可读名字（只列 M1 会遇到的几个）。
fn metal_pixel_format_name(format: u64) -> String {
    match format {
        // 10-bit XR 族（ADR-0010 v3 认这一族；mpv 0.42 在 macOS 上实测是 BGR10A2Unorm）
        94 => "bgr10a2Unorm".to_string(),
        552 => "bgr10_xr".to_string(),
        553 => "bgr10_xr_srgb".to_string(),
        554 => "bgra10_xr".to_string(),
        555 => "bgra10_xr_srgb".to_string(),
        // 16F
        115 => "rgba16float".to_string(),
        // 8bit（用于证明「不成立」）
        70 => "bgra8unorm".to_string(),
        80 => "rgba8unorm".to_string(),
        81 => "rgba8unorm_srgb".to_string(),
        other => format!("mtl#{other}"),
    }
}
