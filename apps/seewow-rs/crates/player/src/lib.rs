//! seewow-player —— 播放宿主（libmpv 自持窗口）、窗口定位、HDR 探针。
//!
//! M1 只有三个模块（任务表 §3.3）：`host`、`window`、`probe`。
//! M3 的 T-09 会把 `host.rs` 里的临时 mpv 调用迁进 `mpv.rs` 并删掉临时代码。

pub mod host;
pub mod probe;
pub mod window;
