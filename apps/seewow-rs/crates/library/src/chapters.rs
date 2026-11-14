//! 片头片尾标记（M3 · T-15 / D-09）。
//!
//! 存的是**用户或自动探测给出的时间点**，不存章节文件本身：
//! - `IntroEnd`：片头结束的位置，起播后可一键跳到这里；
//! - `OutroStart`：片尾开始的位置，到这里提示「下一集」，或按设置直接跳过。
//!
//! 粒度是 `show_key`（一部剧一条），不是单集：同一部剧的片头长度通常一致，逐集存会让
//! 用户标 24 次。需要逐集不同时，调用方在 `show_key` 里带上季集即可，本模块不限制格式。

use rusqlite::{OptionalExtension, params};

use seewow_core::Result;

use crate::db::{Library, db_error};

/// 标记类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChapterKind {
    IntroEnd,
    OutroStart,
}

impl ChapterKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::IntroEnd => "intro_end",
            Self::OutroStart => "outro_start",
        }
    }

    fn from_str(value: &str) -> Option<Self> {
        match value {
            "intro_end" => Some(Self::IntroEnd),
            "outro_start" => Some(Self::OutroStart),
            _ => None,
        }
    }
}

/// 一条标记。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChapterMark {
    pub kind: ChapterKind,
    pub position_ms: i64,
    pub updated_at_ms: i64,
}

impl Library {
    /// 写入或覆盖一条标记。重复调用是幂等的（同一 kind 只留一条）。
    pub fn set_chapter_mark(
        &self,
        show_key: &str,
        kind: ChapterKind,
        position_ms: i64,
        now_ms: i64,
    ) -> Result<()> {
        self.conn
            .execute(
                "INSERT INTO chapter_marks (show_key, kind, position_ms, updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(show_key, kind) DO UPDATE SET
                     position_ms = excluded.position_ms,
                     updated_at_ms = excluded.updated_at_ms",
                params![show_key, kind.as_str(), position_ms.max(0), now_ms],
            )
            .map_err(db_error)?;
        Ok(())
    }

    /// 读一条标记；没有就返回 `None`（调用方据此显示「未设置」而不是 0）。
    pub fn chapter_mark(&self, show_key: &str, kind: ChapterKind) -> Result<Option<ChapterMark>> {
        self.conn
            .query_row(
                "SELECT position_ms, updated_at_ms FROM chapter_marks
                 WHERE show_key = ?1 AND kind = ?2",
                params![show_key, kind.as_str()],
                |row| {
                    Ok(ChapterMark {
                        kind,
                        position_ms: row.get(0)?,
                        updated_at_ms: row.get(1)?,
                    })
                },
            )
            .optional()
            .map_err(db_error)
    }

    /// 读一部剧的全部标记，按时间排序。
    pub fn chapter_marks(&self, show_key: &str) -> Result<Vec<ChapterMark>> {
        let mut statement = self
            .conn
            .prepare(
                "SELECT kind, position_ms, updated_at_ms FROM chapter_marks
                 WHERE show_key = ?1 ORDER BY position_ms",
            )
            .map_err(db_error)?;
        let rows = statement
            .query_map(params![show_key], |row| {
                let kind: String = row.get(0)?;
                Ok((kind, row.get::<_, i64>(1)?, row.get::<_, i64>(2)?))
            })
            .map_err(db_error)?;
        let mut marks = Vec::new();
        for row in rows {
            let (kind, position_ms, updated_at_ms) = row.map_err(db_error)?;
            if let Some(kind) = ChapterKind::from_str(&kind) {
                marks.push(ChapterMark {
                    kind,
                    position_ms,
                    updated_at_ms,
                });
            }
        }
        Ok(marks)
    }

    /// 清掉一部剧的全部标记（用户说「这剧的片头标错了，重来」）。
    pub fn clear_chapter_marks(&self, show_key: &str) -> Result<usize> {
        self.conn
            .execute(
                "DELETE FROM chapter_marks WHERE show_key = ?1",
                params![show_key],
            )
            .map_err(db_error)
    }
}
