//! seewow-app —— composition root。
//!
//! M1 只有 `cli` 与 `main.rs`；M3 起 `playback` 承担播放页的接线决定
//! （起播点 / 片头片尾 / 字幕轨菜单 / 进度落盘），见 T-15。

pub mod playback;

pub use seewow_player as player;
pub use seewow_ui as ui;
