//! SQLite 表结构与版本。
//!
//! 迁移规则：只向前加。user_version 是唯一版本来源；打开库时版本高于本体会直接
//! 报错而不是“尽力而为”，避免新库被旧代码写坏。
//!
//! watch_state 故意**不加外键**：片源被移除或文件暂时不可见时，收藏与进度必须
//! 按稳定 ID 保留下来，等文件回来再接上。这是 M2 DoD 里写明的行为。

/// 当前代码支持的库版本。
pub const SCHEMA_VERSION: i64 = 1;

/// v1：片源、条目、观看状态。
pub const V1: &str = r#"
CREATE TABLE IF NOT EXISTS sources (
    id          TEXT PRIMARY KEY,
    kind        TEXT NOT NULL,
    name        TEXT NOT NULL,
    location    TEXT NOT NULL,
    added_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS media (
    id            TEXT PRIMARY KEY,
    source_id     TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    relative_path TEXT NOT NULL,
    kind          TEXT NOT NULL,
    title         TEXT NOT NULL,
    show_title    TEXT,
    year          INTEGER,
    season        INTEGER,
    episode       INTEGER,
    quality       TEXT NOT NULL DEFAULT '',
    added_at_ms   INTEGER NOT NULL,
    UNIQUE (source_id, relative_path)
);

CREATE INDEX IF NOT EXISTS media_source ON media(source_id);
CREATE INDEX IF NOT EXISTS media_title ON media(title COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS media_added ON media(added_at_ms DESC);

CREATE TABLE IF NOT EXISTS watch_state (
    media_id      TEXT PRIMARY KEY,
    favorite      INTEGER NOT NULL DEFAULT 0,
    watched       INTEGER NOT NULL DEFAULT 0,
    position_ms   INTEGER NOT NULL DEFAULT 0,
    duration_ms   INTEGER,
    updated_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS watch_state_favorite ON watch_state(favorite);
"#;
