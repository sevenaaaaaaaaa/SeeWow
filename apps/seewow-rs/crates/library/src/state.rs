//! 收藏、看过与播放进度。
//!
//! 状态按**稳定 ID** 存，不依赖 media 行：片源移除或文件暂时不见时，收藏与进度
//! 留在库里；文件回来、重扫之后同一个 ID 会重新接上。
//!
//! 每个写方法只更新自己那一列，互不覆盖：标收藏不会把播放进度清零。

use rusqlite::{OptionalExtension, params};

use seewow_core::{MediaEntry, MediaId, Result};

use crate::db::{Library, MEDIA_COLUMNS, db_error, row_to_entry};

/// 一条条目的观看状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct WatchState {
    pub favorite: bool,
    pub watched: bool,
    pub position_ms: i64,
    pub duration_ms: Option<i64>,
    pub updated_at_ms: i64,
}

impl Library {
    pub fn watch_state(&self, id: MediaId) -> Result<Option<WatchState>> {
        self.conn
            .query_row(
                "SELECT favorite, watched, position_ms, duration_ms, updated_at_ms
                 FROM watch_state WHERE media_id = ?1",
                params![id.to_string()],
                |row| {
                    Ok(WatchState {
                        favorite: row.get::<_, i64>(0)? != 0,
                        watched: row.get::<_, i64>(1)? != 0,
                        position_ms: row.get(2)?,
                        duration_ms: row.get(3)?,
                        updated_at_ms: row.get(4)?,
                    })
                },
            )
            .optional()
            .map_err(db_error)
    }

    pub fn set_favorite(&self, id: MediaId, favorite: bool, now_ms: i64) -> Result<()> {
        self.conn
            .execute(
                "INSERT INTO watch_state (media_id, favorite, updated_at_ms)
                 VALUES (?1, ?2, ?3)
                 ON CONFLICT(media_id) DO UPDATE SET
                     favorite = excluded.favorite,
                     updated_at_ms = excluded.updated_at_ms",
                params![id.to_string(), i64::from(favorite), now_ms],
            )
            .map_err(db_error)?;
        Ok(())
    }

    pub fn set_watched(&self, id: MediaId, watched: bool, now_ms: i64) -> Result<()> {
        self.conn
            .execute(
                "INSERT INTO watch_state (media_id, watched, updated_at_ms)
                 VALUES (?1, ?2, ?3)
                 ON CONFLICT(media_id) DO UPDATE SET
                     watched = excluded.watched,
                     updated_at_ms = excluded.updated_at_ms",
                params![id.to_string(), i64::from(watched), now_ms],
            )
            .map_err(db_error)?;
        Ok(())
    }

    /// 写入播放进度。负值直接拒绝；超过已知时长时收敛到时长，不写脏数据。
    /// 不传 duration 时保留库里已有的时长。
    pub fn set_progress(
        &self,
        id: MediaId,
        position_ms: i64,
        duration_ms: Option<i64>,
        now_ms: i64,
    ) -> Result<()> {
        if position_ms < 0 || duration_ms.is_some_and(|duration| duration < 0) {
            return Err(seewow_core::Error::Parse(
                "播放进度或时长不能为负数".to_string(),
            ));
        }
        let position = match duration_ms {
            Some(duration) if duration > 0 => position_ms.min(duration),
            _ => position_ms,
        };
        self.conn
            .execute(
                "INSERT INTO watch_state (media_id, position_ms, duration_ms, updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(media_id) DO UPDATE SET
                     position_ms = excluded.position_ms,
                     duration_ms = COALESCE(excluded.duration_ms, watch_state.duration_ms),
                     updated_at_ms = excluded.updated_at_ms",
                params![id.to_string(), position, duration_ms, now_ms],
            )
            .map_err(db_error)?;
        Ok(())
    }

    /// 收藏列表，最近操作的在前。没有对应 media 行的状态不会出现在列表里。
    pub fn favorites(&self, limit: usize) -> Result<Vec<MediaEntry>> {
        self.entries_joined(
            "w.favorite = 1",
            "ORDER BY w.updated_at_ms DESC, m.title COLLATE NOCASE ASC, m.id ASC",
            limit,
        )
    }

    /// 看过但没看完、进度大于 0 的条目。
    pub fn in_progress(&self, limit: usize) -> Result<Vec<MediaEntry>> {
        self.entries_joined(
            "w.watched = 0 AND w.position_ms > 0",
            "ORDER BY w.updated_at_ms DESC, m.title COLLATE NOCASE ASC, m.id ASC",
            limit,
        )
    }

    fn entries_joined(
        &self,
        condition: &str,
        order: &str,
        limit: usize,
    ) -> Result<Vec<MediaEntry>> {
        let sql = format!(
            "SELECT {} FROM media m JOIN watch_state w ON w.media_id = m.id
             WHERE {condition} {order} LIMIT ?",
            MEDIA_COLUMNS
                .split(", ")
                .map(|column| format!("m.{column}"))
                .collect::<Vec<_>>()
                .join(", ")
        );
        let limit = if limit == 0 { 100 } else { limit };
        let mut statement = self.conn.prepare(&sql).map_err(db_error)?;
        let rows = statement
            .query_map(params![limit as i64], row_to_entry)
            .map_err(db_error)?;
        let mut entries = Vec::new();
        for row in rows {
            entries.push(row.map_err(db_error)?);
        }
        Ok(entries)
    }
}
