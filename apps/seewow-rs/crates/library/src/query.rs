//! 查询：关键词、类型 / 年份 / 画质筛选、排序与分页。
//!
//! 所有用户输入都走参数绑定；LIKE 的 % 与 _ 会被转义，搜索 "100%_" 不会变成通配。
//! 排序一律带 id 作为最后的稳定键，分页不会因同分条目抖动而重复或漏掉。

use rusqlite::params_from_iter;
use rusqlite::types::Value;

use seewow_core::{MediaEntry, MediaKind, Result};

use crate::db::{Library, MEDIA_COLUMNS, db_error, row_to_entry};

/// 排序方式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SortBy {
    /// 最近加入优先（默认）。
    #[default]
    AddedDesc,
    /// 标题升序。
    TitleAsc,
    /// 年份从新到旧，未知年份排最后。
    YearDesc,
}

/// 一次查询。字段全为 None 表示「全部条目」。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Query {
    /// 关键词，匹配标题与剧名。
    pub text: Option<String>,
    pub kind: Option<MediaKind>,
    pub year: Option<i32>,
    /// 画质包含匹配，例如 "4K"。
    pub quality: Option<String>,
    pub sort: SortBy,
    pub limit: usize,
    pub offset: usize,
}

/// 默认每页 100 条，与列表首屏一致。
pub const DEFAULT_LIMIT: usize = 100;

impl Default for Query {
    fn default() -> Self {
        Self {
            text: None,
            kind: None,
            year: None,
            quality: None,
            sort: SortBy::default(),
            limit: DEFAULT_LIMIT,
            offset: 0,
        }
    }
}

impl Query {
    /// 翻页：保留筛选条件，只换 offset。
    pub fn page(mut self, limit: usize, offset: usize) -> Self {
        self.limit = limit;
        self.offset = offset;
        self
    }
}

impl Library {
    pub fn search(&self, query: &Query) -> Result<Vec<MediaEntry>> {
        let (where_sql, mut values) = where_clause(query);
        let limit = if query.limit == 0 {
            DEFAULT_LIMIT
        } else {
            query.limit
        };
        let order = order_clause(query.sort);
        let sql = format!(
            "SELECT {MEDIA_COLUMNS} FROM media{where_sql} ORDER BY {order} LIMIT ? OFFSET ?"
        );
        values.push(Value::Integer(limit as i64));
        values.push(Value::Integer(query.offset as i64));
        let mut statement = self.conn.prepare(&sql).map_err(db_error)?;
        let rows = statement
            .query_map(params_from_iter(values), row_to_entry)
            .map_err(db_error)?;
        let mut entries = Vec::new();
        for row in rows {
            entries.push(row.map_err(db_error)?);
        }
        Ok(entries)
    }

    /// 同一筛选条件下的总数，用于分页。
    pub fn search_count(&self, query: &Query) -> Result<usize> {
        let (where_sql, values) = where_clause(query);
        let sql = format!("SELECT COUNT(*) FROM media{where_sql}");
        let count: i64 = self
            .conn
            .query_row(&sql, params_from_iter(values), |row| row.get(0))
            .map_err(db_error)?;
        Ok(count as usize)
    }
}

fn order_clause(sort: SortBy) -> &'static str {
    match sort {
        SortBy::AddedDesc => "added_at_ms DESC, title COLLATE NOCASE ASC, id ASC",
        SortBy::TitleAsc => "title COLLATE NOCASE ASC, added_at_ms DESC, id ASC",
        SortBy::YearDesc => "year IS NULL ASC, year DESC, title COLLATE NOCASE ASC, id ASC",
    }
}

fn where_clause(query: &Query) -> (String, Vec<Value>) {
    let mut sql = String::from(" WHERE 1 = 1");
    let mut values: Vec<Value> = Vec::new();

    if let Some(text) = query
        .text
        .as_deref()
        .map(str::trim)
        .filter(|text| !text.is_empty())
    {
        sql.push_str(" AND (title LIKE ? ESCAPE '\\' OR show_title LIKE ? ESCAPE '\\')");
        let pattern = like_pattern(text);
        values.push(Value::Text(pattern.clone()));
        values.push(Value::Text(pattern));
    }
    if let Some(kind) = query.kind {
        sql.push_str(" AND kind = ?");
        values.push(Value::Text(kind.as_str().to_string()));
    }
    if let Some(year) = query.year {
        sql.push_str(" AND year = ?");
        values.push(Value::Integer(i64::from(year)));
    }
    if let Some(quality) = query
        .quality
        .as_deref()
        .map(str::trim)
        .filter(|quality| !quality.is_empty())
    {
        sql.push_str(" AND quality LIKE ? ESCAPE '\\'");
        values.push(Value::Text(like_pattern(quality)));
    }

    (sql, values)
}

/// 转义 LIKE 的通配符，再包一层 %：用户输入按字面匹配。
fn like_pattern(input: &str) -> String {
    let mut escaped = String::with_capacity(input.len() + 2);
    for c in input.chars() {
        if matches!(c, '\\' | '%' | '_') {
            escaped.push('\\');
        }
        escaped.push(c);
    }
    format!("%{escaped}%")
}
