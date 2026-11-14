//! seewow-core —— 领域类型、错误、路径、配置、文件名解析。
//!
//! 模块归属：T-02（error / types / paths / config）与 T-04（parse）。
//! 规划、任务表与验收口径见 docs/plan/rust-rewrite-plan.md——那是这条线唯一的权威文件。

pub mod config;
pub mod error;
pub mod keymap;
pub mod parse;
pub mod paths;
pub mod preferences;
pub mod resume;
pub mod subtitle;
pub mod types;

pub use config::Config;
pub use error::{Error, Result};
pub use keymap::{Keymap, PlayerAction, action_for};
pub use parse::{ParsedName, parse_file_name};
pub use paths::{Paths, Platform, current_platform};
pub use preferences::{PlayerPreferences, SleepTimer, TrackInfo};
pub use resume::{ResumePoint, ResumePolicy};
pub use subtitle::{Cue, SubtitleFormat, parse_subtitle};
pub use types::{MediaEntry, MediaId, MediaKind, SourceKind};
