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
}

pub fn region_at(x: f32, y: f32, layout: &Layout, flags: &Flags) -> Region {
    if flags.header_visible && y <= layout.header_h {
        if x < layout.traffic_w && y < layout.header_h {
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

/// 红绿灯：全屏一律不显示；窗口化时悬停（有活动）或指针在左上热区才显示。
pub fn traffic_visible(fullscreen: bool, idle: Duration, x: f32, y: f32, layout: &Layout) -> bool {
    if fullscreen {
        return false;
    }
    let in_hotspot = x < layout.traffic_w && y < layout.header_h;
    in_hotspot || idle < IDLE_HIDE
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
        super::overlay::set_interactive(overlay, region.interactive());
        sink.note_activity();
        return false;
    }

    if kind == NSEventType::LeftMouseDown {
        let (x, y) = pointer_position(event, overlay, &layout);
        let region = region_at(x, y, &layout, &flags);
        super::overlay::set_interactive(overlay, region.interactive());
        sink.note_activity();
        match region {
            Region::Picture => {
                if event.clickCount() >= 2 {
                    sink.toggle_fullscreen();
                } else {
                    sink.toggle_pause();
                }
                return true;
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
