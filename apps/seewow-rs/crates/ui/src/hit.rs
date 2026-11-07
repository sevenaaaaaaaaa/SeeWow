//! 输入路由：**单一主人**（ADR-0003 B1）。
//!
//! - 命中区域是纯函数（`region_at`），几何全部来自 `skeleton.slint` 导出的属性；
//! - 所有鼠标/键盘事件由 `NSEvent` local monitor 统一收（本进程所有窗口）；
//! - 画面区：单击 = 播放/暂停，双击 = 全屏；控制区/页头/探针面板：交给 Slint；
//! - 键盘：空格暂停、F 全屏、Esc 唤出页头、Cmd+W 退出、Cmd+M 最小化、Cmd+Ctrl+F 全屏；
//!   带 Cmd 的其它组合一律放行（不吞系统快捷键）。

use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use block2::RcBlock;
use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2_app_kit::{NSEvent, NSEventMask, NSEventModifierFlags, NSEventType, NSWindow};

/// 指针静止多久开始收页头 / 控制条（负责人要求 3 秒）。
pub const IDLE_HIDE: Duration = Duration::from_millis(3000);

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

impl Rect {
    pub fn contains(&self, x: f32, y: f32) -> bool {
        x >= self.x && x <= self.x + self.w && y >= self.y && y <= self.y + self.h
    }
}

/// 几何契约：全部来自 `skeleton.slint` 的 `out property`。
#[derive(Clone, Copy, Debug, Default)]
pub struct Layout {
    pub width: f32,
    pub height: f32,
    pub header_h: f32,
    pub gutter: f32,
    pub controls_h: f32,
    pub traffic_w: f32,
    pub traffic_h: f32,
    pub probe_w: f32,
    pub probe_h: f32,
    pub top_edge: f32,
    pub header_actions_w: f32,
}

impl Layout {
    pub fn probe_rect(&self) -> Rect {
        Rect {
            x: self.width - self.gutter - self.probe_w,
            y: self.header_h + 14.0,
            w: self.probe_w,
            h: self.probe_h,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Flags {
    pub playing: bool,
    pub fullscreen: bool,
    pub header_visible: bool,
    pub controls_visible: bool,
    pub probe_visible: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Region {
    /// 左上角红绿灯热区
    Traffic,
    /// 页头右侧的两个按钮（交给 Slint）
    HeaderActions,
    /// 页头其余部分：拖窗
    HeaderDrag,
    /// 底部控制条（交给 Slint）
    Controls,
    /// 探针面板（交给 Slint）
    Probe,
    /// 画面区：穿透给「没人」，由这里做播放器动作
    Picture,
}

impl Region {
    /// 这些区域要关掉穿透，让 Slint 收事件。
    pub fn interactive(self) -> bool {
        matches!(
            self,
            Region::Traffic | Region::HeaderActions | Region::Controls | Region::Probe
        )
    }

    /// 是否要关掉穿透。**没在播放时画面区也交给 Slint** ——
    /// 否则壳中央那个「打开文件」按钮永远点不到（评审 P2：死控件）。
    pub fn interactive_given(self, playing: bool) -> bool {
        self.interactive() || (!playing && matches!(self, Region::Picture))
    }
}

pub fn region_at(x: f32, y: f32, layout: &Layout, flags: &Flags) -> Region {
    if flags.header_visible && y <= layout.header_h {
        // 热区高度是 traffic_h（DoD 的 32），不是页头高度：否则 (40,33) 会被判成红绿灯
        if x < layout.traffic_w && y < layout.traffic_h {
            return Region::Traffic;
        }
        if x >= layout.width - layout.gutter - layout.header_actions_w {
            return Region::HeaderActions;
        }
        return Region::HeaderDrag;
    }
    if flags.probe_visible && layout.probe_rect().contains(x, y) {
        return Region::Probe;
    }
    if y >= layout.height - layout.controls_h {
        return Region::Controls;
    }
    Region::Picture
}

/// 页头要不要显示：窗口化常显（否则没地方拖窗）；全屏时按静止计时器，暂停常显。
pub fn header_visible(
    playing: bool,
    fullscreen: bool,
    idle: Duration,
    pointer_at_top: bool,
) -> bool {
    if !fullscreen || !playing {
        return true;
    }
    idle < IDLE_HIDE || pointer_at_top
}

/// 控制条：动就出，静止 3 秒收。
pub fn controls_visible(idle: Duration) -> bool {
    idle < IDLE_HIDE
}

/// 红绿灯：**只有「窗口化 + 非全屏 + 指针在左上热区（traffic_w × traffic_h）」才显示**。
///
/// `_idle` 保留在签名里只是为了兼容 QA 的 harness（它按这个签名断言）；
/// 显示与否与「静止多久」无关 —— 评审 case-05 就是被「跟着页头可见走」判失败的。
pub fn traffic_visible(fullscreen: bool, _idle: Duration, x: f32, y: f32, layout: &Layout) -> bool {
    if fullscreen {
        return false;
    }
    x >= 0.0 && y >= 0.0 && x < layout.traffic_w && y < layout.traffic_h
}

/// 面板/播放状态由 app 实现；hit 只管「事件该变成哪个动作」。
pub trait InputSink {
    fn toggle_pause(&self);
    fn toggle_fullscreen(&self);
    fn request_shutdown(&self);
    fn minimize(&self);
    /// 指针动过（重置 3 秒计时、刷新页头/控制条）
    fn note_activity(&self);
}

/// 主线程共享的手势状态。
pub struct Shared {
    pub layout: Mutex<Layout>,
    pub flags: Mutex<Flags>,
    pub last_activity: Mutex<Instant>,
    /// 指针在叠层窗口里的位置（逻辑坐标，原点左上）
    pub pointer: Mutex<(f32, f32)>,
}

impl Shared {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            layout: Mutex::new(Layout::default()),
            flags: Mutex::new(Flags::default()),
            last_activity: Mutex::new(Instant::now()),
            pointer: Mutex::new((0.0, 0.0)),
        })
    }

    pub fn idle(&self) -> Duration {
        self.last_activity
            .lock()
            .map(|t| t.elapsed())
            .unwrap_or_default()
    }

    pub fn touch(&self) {
        if let Ok(mut slot) = self.last_activity.lock() {
            *slot = Instant::now();
        }
    }

    pub fn pointer(&self) -> (f32, f32) {
        self.pointer.lock().map(|p| *p).unwrap_or((0.0, 0.0))
    }

    pub fn set_pointer(&self, x: f32, y: f32) {
        if let Ok(mut slot) = self.pointer.lock() {
            *slot = (x, y);
        }
    }
}

/// 装好的监视器：丢掉它就等于拆掉（AppKit 的 monitor 随对象释放注销）。
pub struct InputMonitor {
    _monitor: Retained<AnyObject>,
    _block: RcBlock<dyn Fn(std::ptr::NonNull<NSEvent>) -> *mut NSEvent>,
}

/// 安装 `NSEvent` local monitor。**必须在主线程调用。**
pub fn install(
    host: Retained<NSWindow>,
    overlay: Retained<NSWindow>,
    shared: Arc<Shared>,
    sink: Rc<dyn InputSink>,
) -> Option<InputMonitor> {
    let mask = NSEventMask::MouseMoved
        | NSEventMask::LeftMouseDown
        | NSEventMask::LeftMouseUp
        | NSEventMask::LeftMouseDragged
        | NSEventMask::ScrollWheel
        | NSEventMask::KeyDown
        | NSEventMask::FlagsChanged;

    let block = RcBlock::new(move |event: std::ptr::NonNull<NSEvent>| -> *mut NSEvent {
        let event_ref = unsafe { event.as_ref() };
        let consumed = handle(event_ref, &host, &overlay, &shared, sink.as_ref());
        if consumed {
            std::ptr::null_mut()
        } else {
            event.as_ptr()
        }
    });

    let monitor = unsafe { NSEvent::addLocalMonitorForEventsMatchingMask_handler(mask, &block) }?;
    Some(InputMonitor {
        _monitor: monitor,
        _block: block,
    })
}

/// 返回 true = 吞掉事件（不给任何人）。
fn handle(
    event: &NSEvent,
    host: &NSWindow,
    overlay: &NSWindow,
    shared: &Shared,
    sink: &dyn InputSink,
) -> bool {
    let kind = event.r#type();
    let (layout, flags) = {
        let layout = shared.layout.lock().map(|l| *l).unwrap_or_default();
        let flags = shared.flags.lock().map(|f| *f).unwrap_or_default();
        (layout, flags)
    };

    if kind == NSEventType::MouseMoved || kind == NSEventType::LeftMouseDragged {
        let (x, y) = pointer_position(event, overlay, &layout);
        shared.set_pointer(x, y);
        let region = region_at(x, y, &layout, &flags);
        let interactive = region.interactive_given(flags.playing);
        // 离开交互区要把 key 交还宿主窗口，否则键盘焦点一直挂在叠层上（评审 P2）
        let was_interactive = !overlay.ignoresMouseEvents();
        super::overlay::set_interactive(overlay, interactive);
        if was_interactive && !interactive {
            host.makeKeyWindow();
        }
        sink.note_activity();
        return false;
    }

    if kind == NSEventType::LeftMouseDown {
        let (x, y) = pointer_position(event, overlay, &layout);
        let region = region_at(x, y, &layout, &flags);
        super::overlay::set_interactive(overlay, region.interactive_given(flags.playing));
        sink.note_activity();
        match region {
            Region::Picture if flags.playing => {
                if event.clickCount() >= 2 {
                    sink.toggle_fullscreen();
                } else {
                    sink.toggle_pause();
                }
                return true;
            }
            Region::Picture => {
                // 未播放：画面区归 Slint（中央按钮/提示可点）
                return false;
            }
            Region::HeaderDrag => {
                // 页头拖窗：AppKit 自己跑拖动循环，子窗口跟着父窗口走。
                host.performWindowDragWithEvent(event);
                return true;
            }
            Region::Traffic | Region::HeaderActions | Region::Controls | Region::Probe => {
                // 交给 Slint 的按钮 / 进度条
                return false;
            }
        }
    }

    if kind == NSEventType::LeftMouseUp || kind == NSEventType::ScrollWheel {
        sink.note_activity();
        let (x, y) = pointer_position(event, overlay, &layout);
        let region = region_at(x, y, &layout, &flags);
        super::overlay::set_interactive(overlay, region.interactive());
        return false;
    }

    if kind == NSEventType::KeyDown {
        // 模态面板（NSOpenPanel）或文本输入期间一律放行：否则打开文件的对话框里
        // 空格/Esc/方向键会被我们吞掉（评审 P1-6）
        if modal_or_text_input_active() {
            return false;
        }
        let key = event.keyCode();
        let mods = event.modifierFlags();
        let command = mods.contains(NSEventModifierFlags::Command);
        let control = mods.contains(NSEventModifierFlags::Control);

        // Cmd 组合里只有 Cmd+W / Cmd+M / Cmd+Ctrl+F 归我们，其它一律放行（Cmd+Q、Cmd+Tab…）。
        if command {
            match key {
                13 => {
                    sink.request_shutdown();
                    return true;
                }
                46 => {
                    sink.minimize();
                    return true;
                }
                3 if control => {
                    sink.toggle_fullscreen();
                    return true;
                }
                _ => return false,
            }
        }

        match key {
            49 => {
                sink.toggle_pause();
                return true;
            }
            53 => {
                // Esc：唤出页头（全屏时先出现页头，再按一次由调用方处理）
                sink.note_activity();
                return true;
            }
            3 => {
                sink.toggle_fullscreen();
                return true;
            }
            _ => return false,
        }
    }

    false
}

/// `NSApp` 是否处于模态 / 当前焦点是不是文本输入。
fn modal_or_text_input_active() -> bool {
    use objc2_app_kit::NSApplication;
    let Some(mtm) = objc2::MainThreadMarker::new() else {
        return false;
    };
    let app = NSApplication::sharedApplication(mtm);
    if app.modalWindow().is_some() {
        return true;
    }
    // 文本焦点：first responder 的类名里带 Text/FieldEditor 就放行
    let Some(window) = app.keyWindow() else {
        return false;
    };
    let Some(responder) = window.firstResponder() else {
        return false;
    };
    let class: *const objc2::runtime::AnyClass = unsafe { objc2::msg_send![&*responder, class] };
    if class.is_null() {
        return false;
    }
    let name = unsafe { (*class).name().to_string_lossy().into_owned() };
    name.contains("Text") || name.contains("FieldEditor")
}

/// 事件坐标 → 叠层窗口的左上角原点逻辑坐标。
fn pointer_position(event: &NSEvent, overlay: &NSWindow, layout: &Layout) -> (f32, f32) {
    let point = event.locationInWindow();
    let height = if layout.height > 0.0 {
        layout.height as f64
    } else {
        overlay.frame().size.height
    };
    (point.x as f32, (height - point.y) as f32)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn layout() -> Layout {
        Layout {
            width: 1200.0,
            height: 760.0,
            header_h: 56.0,
            gutter: 34.0,
            controls_h: 72.0,
            traffic_w: 80.0,
            traffic_h: 32.0,
            probe_w: 420.0,
            probe_h: 352.0,
            top_edge: 8.0,
            header_actions_w: 182.0,
        }
    }

    fn flags() -> Flags {
        Flags {
            header_visible: true,
            ..Default::default()
        }
    }

    /// 热区内（40,20）显示；热区右侧 1px（81,31）不显示。
    #[test]
    fn traffic_only_inside_hotspot_width() {
        assert!(traffic_visible(
            false,
            Duration::from_secs(10),
            40.0,
            20.0,
            &layout()
        ));
        assert!(!traffic_visible(
            false,
            Duration::from_secs(10),
            81.0,
            31.0,
            &layout()
        ));
    }

    /// 热区下方 1px（40,33）不显示 —— 热区高度是 32，不是页头高度 56。
    #[test]
    fn traffic_only_inside_hotspot_height() {
        assert!(!traffic_visible(
            false,
            Duration::from_secs(10),
            40.0,
            33.0,
            &layout()
        ));
    }

    /// 指针不在热区时，静止多久都不显示（默认隐藏）。
    #[test]
    fn traffic_hidden_when_pointer_outside_hotspot_regardless_of_idle() {
        assert!(!traffic_visible(
            false,
            Duration::from_millis(0),
            900.0,
            500.0,
            &layout()
        ));
        assert!(!traffic_visible(
            false,
            Duration::from_secs(30),
            900.0,
            500.0,
            &layout()
        ));
    }

    /// 全屏一律不显示。
    #[test]
    fn traffic_never_visible_in_fullscreen() {
        assert!(!traffic_visible(
            true,
            Duration::from_millis(0),
            1.0,
            1.0,
            &layout()
        ));
    }

    /// (40,33) 是页头拖动区，(40,20) 才是红绿灯区。
    #[test]
    fn region_split_uses_hotspot_height() {
        assert_eq!(region_at(40.0, 20.0, &layout(), &flags()), Region::Traffic);
        assert_eq!(
            region_at(40.0, 33.0, &layout(), &flags()),
            Region::HeaderDrag
        );
    }

    /// 页头空白处是拖动区，最右侧是按钮区。
    #[test]
    fn header_middle_drags_and_right_edge_is_actions() {
        assert_eq!(
            region_at(600.0, 10.0, &layout(), &flags()),
            Region::HeaderDrag
        );
        assert_eq!(
            region_at(1180.0, 10.0, &layout(), &flags()),
            Region::HeaderActions
        );
    }
}
