//! 叠层窗口（Slint）的 AppKit 配置：透明、无边框、挂在 mpv 窗口下、跟随全屏与换屏。
//!
//! 窗口方案（HLD §2.3 / §9.2 / ADR-0003 A1）：mpv 自持窗口 P，我们把 Slint 的窗口 S
//! 作为它的子窗口 `P.addChildWindow(S, .above)`。子窗口由 AppKit 保证跟随父窗口的
//! 移动、缩放、最小化与全屏 Space（配 `.fullScreenAuxiliary` + `.moveToActiveSpace`）。
//!
//! 透明：Slint 的窗口声明成 `no-frame: true` + `background: transparent`，
//! winit 后端就会用 `with_transparent(true)` 建窗（`i-slint-backend-winit` 的
//! `wants_transparent` =「背景不不透明 或 no_frame」），AppKit 侧再做加固。

use objc2::msg_send;
use objc2::rc::Retained;
use objc2::runtime::AnyClass;
use objc2_app_kit::{
    NSApplication, NSColor, NSWindow, NSWindowCollectionBehavior, NSWindowOrderingMode,
    NSWindowStyleMask,
};
use objc2_foundation::{NSArray, NSRect};

/// Slint 窗口的标题 —— 用于在 `NSApp.windows` 里认出自己的窗口。
pub const OVERLAY_WINDOW_TITLE: &str = "SeeWow Overlay";

/// 挂载结果，全部写进 m1.log（V1 / V2 的证据）。
#[derive(Clone, Debug, Default)]
pub struct AttachReport {
    pub overlay_window: isize,
    pub host_window: isize,
    pub style_mask: u64,
    pub opaque: bool,
    pub has_shadow: bool,
    pub collection_behavior: u64,
    pub ignores_mouse: bool,
    pub frame: (f64, f64, f64, f64),
    pub parent_is_host: bool,
    pub title_ok: bool,
}

impl AttachReport {
    pub fn log_line(&self) -> String {
        let (fx, fy, fw, fh) = self.frame;
        format!(
            "overlay: 已挂载 overlay=#{} host=#{} styleMask=0x{:x} opaque={} hasShadow={} collectionBehavior=0x{:x} ignoresMouse={} frame={{{fx:.0},{fy:.0} {fw:.0}x{fh:.0}}} parentIsHost={} title={:?}",
            self.overlay_window,
            self.host_window,
            self.style_mask,
            self.opaque,
            self.has_shadow,
            self.collection_behavior,
            self.ignores_mouse,
            self.parent_is_host,
            OVERLAY_WINDOW_TITLE,
        )
    }
}

pub fn main_thread() -> Option<objc2::MainThreadMarker> {
    objc2::MainThreadMarker::new()
}

/// 在 `NSApp.windows` 里按标题找 Slint 的叠层窗口（不阻塞）。
pub fn find_overlay_window() -> Option<Retained<NSWindow>> {
    let mtm = main_thread()?;
    let app = NSApplication::sharedApplication(mtm);
    let windows: Retained<NSArray<NSWindow>> = app.windows();
    // 同 player::window：不用 isEqualToString:（Swift 桥接的返回编码与 BOOL 不符）
    for index in 0..windows.count() {
        let window = windows.objectAtIndex(index);
        if window.title().to_string() == OVERLAY_WINDOW_TITLE {
            return Some(window);
        }
    }
    None
}

pub fn window_class(window: &NSWindow) -> String {
    let cls: *const AnyClass = unsafe { msg_send![window, class] };
    if cls.is_null() {
        return "n/a".to_string();
    }
    unsafe { (*cls).name().to_string_lossy().into_owned() }
}

pub fn frame(window: &NSWindow) -> (f64, f64, f64, f64) {
    let rect: NSRect = window.frame();
    (
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height,
    )
}

pub fn screen_name(window: &NSWindow) -> String {
    window
        .screen()
        .map(|screen| screen.localizedName().to_string())
        .unwrap_or_else(|| "n/a".to_string())
}

/// 关掉/打开鼠标穿透：控制区与页头要能被 Slint 点到，画面区保持穿透。
pub fn set_interactive(overlay: &NSWindow, interactive: bool) {
    if overlay.ignoresMouseEvents() != !interactive {
        overlay.setIgnoresMouseEvents(!interactive);
    }
    // 控制区可交互时要成为 key window，否则第一次点击只激活窗口、点不到按钮（HLD §2.4）
    if interactive && !overlay.isKeyWindow() {
        overlay.makeKeyAndOrderFront(None);
    }
}

/// 还没有 mpv 窗口时先把壳窗口自己显示出来（否则什么都不显示）。
///
/// 这是 HLD §9.6「已知降级」的温和版本：壳先独立存在，用户能在里面点「打开文件」；
/// mpv 的窗口一出现，下一 tick 就走 `attach` 把它收成子窗口。
pub fn configure_standalone(overlay: &NSWindow) -> (u64, bool) {
    overlay.setOpaque(false);
    overlay.setBackgroundColor(Some(&NSColor::clearColor()));
    overlay.setHasShadow(false);
    overlay.setMovableByWindowBackground(false);
    if overlay.styleMask().contains(NSWindowStyleMask::Titled) {
        overlay.setStyleMask(NSWindowStyleMask::Borderless);
    }
    // 独立存在时允许交互（否则按钮点不到）
    overlay.setIgnoresMouseEvents(false);
    overlay.setAcceptsMouseMovedEvents(true);
    overlay.orderFront(None);
    (overlay.styleMask().0 as u64, overlay.isOpaque())
}

/// 把 S 挂成 P 的子窗口并做透明加固。**必须在主线程、S 已经 `show()` 之后调用。**
pub fn attach(overlay: &NSWindow, host: &NSWindow) -> AttachReport {
    // 1) 透明：不透明窗口会盖住视频（白底闪屏的根源之一）
    overlay.setOpaque(false);
    overlay.setBackgroundColor(Some(&NSColor::clearColor()));
    overlay.setHasShadow(false);
    overlay.setMovableByWindowBackground(false);

    // 2) 无边框：Slint 的 `no-frame` 已经建出 borderless；若实际带了标题栏就纠正一次
    let mask = overlay.styleMask();
    if mask.contains(NSWindowStyleMask::Titled) {
        overlay.setStyleMask(NSWindowStyleMask::Borderless);
    }
    let style_mask = overlay.styleMask().0 as u64;

    // 3) 鼠标：默认穿透（画面区），命中控制区时由 hit.rs 打开
    overlay.setIgnoresMouseEvents(true);
    overlay.setAcceptsMouseMovedEvents(true);

    // 4) 跟随全屏 Space + 跟随当前 Space
    let behavior = NSWindowCollectionBehavior::FullScreenAuxiliary
        | NSWindowCollectionBehavior::MoveToActiveSpace;
    overlay.setCollectionBehavior(behavior);

    // 5) 尺寸对齐宿主窗口（两者都无边框，frame 即内容区）
    let host_rect: NSRect = host.frame();
    overlay.setFrame_display(host_rect, true);

    // 6) 父子关系：P 加 S，S 在 P 之上
    unsafe { host.addChildWindow_ordered(overlay, NSWindowOrderingMode::Above) };

    // 7) 显示，但不 makeKey（键盘走 local monitor）
    overlay.orderFront(None);

    let parent_is_host = overlay
        .parentWindow()
        .map(|parent| std::ptr::eq(Retained::as_ptr(&parent), host as *const NSWindow))
        .unwrap_or(false);

    AttachReport {
        overlay_window: overlay.windowNumber(),
        host_window: host.windowNumber(),
        style_mask,
        opaque: overlay.isOpaque(),
        has_shadow: overlay.hasShadow(),
        collection_behavior: overlay.collectionBehavior().0 as u64,
        ignores_mouse: overlay.ignoresMouseEvents(),
        frame: frame(overlay),
        parent_is_host,
        title_ok: true,
    }
}

/// 每 100ms 对一次 frame：子窗口不随父窗口 resize/全屏自动改尺寸，必须自己跟。
/// 返回 true 表示这次真的改了。
pub fn sync_frame(overlay: &NSWindow, host: &NSWindow) -> bool {
    let target: NSRect = host.frame();
    let current: NSRect = overlay.frame();
    // 2px 容差：AppKit 对子窗口的 frame 会做取整/吸附，半像素级差异反复 setFrame
    // 只会每帧写日志、每秒重设 10 次窗口（实测过这个坑）。
    let same = (target.origin.x - current.origin.x).abs() < 2.0
        && (target.origin.y - current.origin.y).abs() < 2.0
        && (target.size.width - current.size.width).abs() < 2.0
        && (target.size.height - current.size.height).abs() < 2.0;
    if same {
        return false;
    }
    overlay.setFrame_display(target, true);
    true
}

/// 关闭顺序第一步：叠层先 orderOut，再让 mpv 收 quit（HLD §2.3）。
pub fn order_out(overlay: &NSWindow) {
    overlay.orderOut(None);
}

/// 从父窗口上摘掉（退出时不留悬挂关系）。
pub fn detach_child(host: &NSWindow, overlay: &NSWindow) {
    host.removeChildWindow(overlay);
}
