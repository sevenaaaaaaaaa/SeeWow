//! seewow-ui —— Slint 界面壳（M1 走通骨架）。
//!
//! M1 只有三个模块（任务表 §3.3）：`overlay`（窗口层）、`hit`（输入路由）、
//! `skeleton`（壳组件的 Rust 侧）。视图与设计令牌由 M2 / M6 的任务各自追加。

pub mod hit;
pub mod overlay;
pub mod skeleton;
