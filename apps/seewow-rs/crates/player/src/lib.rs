//! seewow-player —— 播放宿主（libmpv 自持窗口）、窗口定位、HDR 探针。
//!
//! 模块：`mpv`（libmpv 封装与播放线程）、`host`（M1 日志门面与句柄）、`window`（窗口定位）、
//! `probe`（HDR 判定）。M3 T-09 已把 M1 散在 `host.rs` 里的 libmpv 调用收编进 `mpv.rs`。

pub mod host;
pub mod mpv;
pub mod probe;
pub mod window;
