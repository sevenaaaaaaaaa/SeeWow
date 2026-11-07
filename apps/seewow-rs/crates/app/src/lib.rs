//! seewow-app —— composition root。
//!
//! M1 还没有 `perf` 之类的子模块（T-33 才追加）；app 的组装逻辑写在 `main.rs`。

pub use seewow_player as player;
pub use seewow_ui as ui;
