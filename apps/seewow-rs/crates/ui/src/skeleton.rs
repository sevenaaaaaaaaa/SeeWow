//! 壳组件的 Rust 侧：创建、状态推送、回调接线。
//!
//! Slint 生成代码由 `build.rs` 编译 `ui/app.slint` 得到（`Skeleton` 继承 `Skeleton`）。

slint::include_modules!();

/// 壳。持有一个 Slint 组件句柄；窗口相关动作走 `overlay`，输入路由走 `hit`。
pub struct Shell {
    ui: Skeleton,
}

impl Shell {
    pub fn new() -> Result<Self, slint::PlatformError> {
        Ok(Self {
            ui: Skeleton::new()?,
        })
    }

    pub fn ui(&self) -> &Skeleton {
        &self.ui
    }

    pub fn weak(&self) -> slint::Weak<Skeleton> {
        self.ui.as_weak()
    }

    pub fn window(&self) -> &slint::Window {
        self.ui.window()
    }

    pub fn show(&self) -> Result<(), slint::PlatformError> {
        self.ui.show()
    }

    pub fn hide(&self) {
        let _ = self.ui.hide();
    }

    pub fn request_redraw(&self) {
        self.ui.window().request_redraw();
    }
}

/// `mm:ss / mm:ss`：M1 只要看得懂，不做 1.0.0 的排版细节。
pub fn clock_label(position: Option<f64>, duration: Option<f64>) -> String {
    fn one(seconds: f64) -> String {
        let total = if seconds.is_finite() && seconds > 0.0 {
            seconds as u64
        } else {
            0
        };
        format!("{:02}:{:02}", total / 60, total % 60)
    }
    match (position, duration) {
        (Some(position), Some(duration)) => format!("{} / {}", one(position), one(duration)),
        _ => "00:00 / 00:00".to_string(),
    }
}
