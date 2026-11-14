//! 片库句柄：打开、迁移、写入与读取。
//!
//! 线程约定：Connection 不是 Sync，M2 由单个扫描线程持有；跨线程共享留到需要时再
//! 设计，不提前套 Mutex。

use std::collections::HashSet;
use std::path::Path;
use std::time::Duration;

use rusqlite::{Connection, OptionalExtension, params};

use seewow_core::{Error, MediaEntry, MediaId, MediaKind, Result, SourceKind};

use crate::schema::{SCHEMA_VERSION, V1};

/// 一个已打开的片库。
pub struct Library {
    pub(crate) conn: Connection,
}

impl std::fmt::Debug for Library {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Library").finish_non_exhaustive()
    }
}

impl Library {
    /// 打开（必要时创建）文件库，并跑到最新版本。
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(path).map_err(db_error)?;
        Self::from_connection(conn)
    }

    /// 测试与临时查询用的内存库。
    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory().map_err(db_error)?;
        Self::from_connection(conn)
    }

    fn from_connection(conn: Connection) -> Result<Self> {
        let mut library = Self { conn };
        library.configure()?;
        library.migrate()?;
        Ok(library)
    }

    fn configure(&mut self) -> Result<()> {
        self.conn
            .busy_timeout(Duration::from_secs(5))
            .map_err(db_error)?;
        self.conn
            .execute_batch("PRAGMA foreign_keys = ON;")
            .map_err(db_error)?;
        Ok(())
    }

    fn migrate(&mut self) -> Result<()> {
        let version: i64 = self
            .conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .map_err(db_error)?;
        if version > SCHEMA_VERSION {
            return Err(Error::Db(format!(
                "片库版本 {version} 高于当前应用支持的 {SCHEMA_VERSION}，请升级应用后再打开"
            )));
        }
        if version < 1 {
            let tx = self.conn.transaction().map_err(db_error)?;
            tx.execute_batch(V1).map_err(db_error)?;
            tx.pragma_update(None, "user_version", 1)
                .map_err(db_error)?;
            tx.commit().map_err(db_error)?;
        }
        Ok(())
    }

    pub fn schema_version(&self) -> Result<i64> {
        self.conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .map_err(db_error)
    }

    /// 写入或更新一条片源。重复调用不会重复登记。
    pub fn upsert_source(
        &self,
        id: &str,
        kind: SourceKind,
        name: &str,
        location: &str,
        added_at_ms: i64,
    ) -> Result<()> {
        self.conn
            .execute(
                "INSERT INTO sources (id, kind, name, location, added_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(id) DO UPDATE SET
                     kind = excluded.kind,
                     name = excluded.name,
                     location = excluded.location",
                params![id, kind.as_str(), name, location, added_at_ms],
            )
            .map_err(db_error)?;
        Ok(())
    }

    /// 删除片源；其下条目随外键级联删除，观看状态按稳定 ID 保留。
    pub fn delete_source(&self, id: &str) -> Result<usize> {
        self.conn
            .execute("DELETE FROM sources WHERE id = ?1", params![id])
            .map_err(db_error)
    }

    pub fn source_count(&self) -> Result<usize> {
        let count: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM sources", [], |row| row.get(0))
            .map_err(db_error)?;
        Ok(count as usize)
    }

    /// 批量写入条目。已存在的条目更新可变的展示字段，但**保留首次加入时间**。
    /// 返回受影响的行数（新增与更新都算）。
    pub fn upsert_media(&mut self, entries: &[MediaEntry]) -> Result<usize> {
        let tx = self.conn.transaction().map_err(db_error)?;
        {
            let mut statement = tx
                .prepare(
                    "INSERT INTO media
                        (id, source_id, relative_path, kind, title, show_title,
                         year, season, episode, quality, added_at_ms)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
                     ON CONFLICT(id) DO UPDATE SET
                         kind = excluded.kind,
                         title = excluded.title,
                         show_title = excluded.show_title,
                         year = excluded.year,
                         season = excluded.season,
                         episode = excluded.episode,
                         quality = excluded.quality",
                )
                .map_err(db_error)?;
            for entry in entries {
                let path = entry.relative_path.to_string_lossy().to_string();
                statement
                    .execute(params![
                        entry.id.to_string(),
                        &entry.source_id,
                        path,
                        entry.kind.as_str(),
                        &entry.title,
                        &entry.show_title,
                        entry.year,
                        entry.season,
                        entry.episode,
                        &entry.quality,
                        entry.added_at_ms,
                    ])
                    .map_err(db_error)?;
            }
        }
        tx.commit().map_err(db_error)?;
        Ok(entries.len())
    }

    pub fn count_media(&self) -> Result<usize> {
        let count: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM media", [], |row| row.get(0))
            .map_err(db_error)?;
        Ok(count as usize)
    }

    /// 某个片源下已经存在的条目 ID，用于区分「新增」与「更新」。
    pub fn existing_ids(&self, source_id: &str) -> Result<HashSet<MediaId>> {
        let mut statement = self
            .conn
            .prepare("SELECT id FROM media WHERE source_id = ?1")
            .map_err(db_error)?;
        let rows = statement
            .query_map(params![source_id], |row| row.get::<_, String>(0))
            .map_err(db_error)?;
        let mut ids = HashSet::new();
        for row in rows {
            let text = row.map_err(db_error)?;
            if let Ok(raw) = u64::from_str_radix(&text, 16) {
                ids.insert(MediaId::from_raw(raw));
            }
        }
        Ok(ids)
    }

    /// 读取全部条目，按加入时间从新到旧。
    pub fn all_media(&self) -> Result<Vec<MediaEntry>> {
        let mut statement = self
            .conn
            .prepare(&format!(
                "SELECT {MEDIA_COLUMNS} FROM media ORDER BY added_at_ms DESC, title COLLATE NOCASE"
            ))
            .map_err(db_error)?;
        let rows = statement.query_map([], row_to_entry).map_err(db_error)?;
        let mut entries = Vec::new();
        for row in rows {
            entries.push(row.map_err(db_error)?);
        }
        Ok(entries)
    }

    pub fn media_by_id(&self, id: MediaId) -> Result<Option<MediaEntry>> {
        self.conn
            .query_row(
                &format!("SELECT {MEDIA_COLUMNS} FROM media WHERE id = ?1"),
                params![id.to_string()],
                row_to_entry,
            )
            .optional()
            .map_err(db_error)
    }
}

/// media 表的列顺序；db 与 query 共用，避免两处手写列名漂移。
pub(crate) const MEDIA_COLUMNS: &str = "id, source_id, relative_path, kind, title, show_title, year, season, episode, quality, added_at_ms";

pub(crate) fn row_to_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<MediaEntry> {
    let id: String = row.get(0)?;
    let raw = u64::from_str_radix(&id, 16).unwrap_or(0);
    let kind: String = row.get(3)?;
    Ok(MediaEntry {
        id: MediaId::from_raw(raw),
        source_id: row.get(1)?,
        relative_path: std::path::PathBuf::from(row.get::<_, String>(2)?),
        // 未知种类归到 Other：旧库或手工改过库不该让整次读取失败。
        kind: MediaKind::from_code(&kind).unwrap_or(MediaKind::Other),
        title: row.get(4)?,
        show_title: row.get(5)?,
        year: row.get(6)?,
        season: row.get::<_, Option<i64>>(7)?.map(|value| value as u32),
        episode: row.get::<_, Option<i64>>(8)?.map(|value| value as u32),
        quality: row.get(9)?,
        added_at_ms: row.get(10)?,
    })
}

pub(crate) fn db_error(error: rusqlite::Error) -> Error {
    Error::Db(error.to_string())
}
