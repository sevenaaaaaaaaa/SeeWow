//! seewow-library —— SQLite 片库、扫描、查询、观看状态。
//!
//! 任务归属：T-03（db / schema）、T-05（scan）、T-06（query）、T-07（state）。
//! 规划与验收见 docs/plan/rust-rewrite-plan.md。

pub mod db;
pub mod query;
pub mod scan;
pub mod schema;

pub use db::Library;
pub use query::{DEFAULT_LIMIT, Query, SortBy};
pub use scan::{ScanFailure, ScanOptions, ScanReport, collect_media, scan_into_library};
