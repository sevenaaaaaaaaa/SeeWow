//! T-03 验收：建库、迁移、片源与条目的写入语义。
//!
//! 这些测试直接打公开 API，不碰私有字段；临时库文件放在系统临时目录，结束即删。

use std::path::PathBuf;

use rusqlite::Connection;
use seewow_core::{MediaEntry, MediaId, MediaKind, SourceKind};
use seewow_library::Library;

fn temp_db(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!("seewow-library-{}-{tag}.db", std::process::id()))
}

fn entry(source: &str, path: &str, title: &str, added_at_ms: i64) -> MediaEntry {
    MediaEntry {
        id: MediaId::from_parts(source, path),
        source_id: source.to_string(),
        relative_path: PathBuf::from(path),
        kind: MediaKind::Movie,
        title: title.to_string(),
        show_title: None,
        year: Some(2024),
        season: None,
        episode: None,
        quality: "4K".to_string(),
        added_at_ms,
    }
}

#[test]
fn fresh_library_is_versioned_and_empty() {
    let library = Library::open_in_memory().unwrap();
    assert_eq!(library.schema_version().unwrap(), 1);
    assert_eq!(library.count_media().unwrap(), 0);
    assert_eq!(library.source_count().unwrap(), 0);
    assert!(library.all_media().unwrap().is_empty());
}

#[test]
fn reopening_the_same_file_does_not_rerun_migrations() {
    let path = temp_db("reopen");
    let _ = std::fs::remove_file(&path);
    {
        let library = Library::open(&path).unwrap();
        assert_eq!(library.schema_version().unwrap(), 1);
    }
    {
        let library = Library::open(&path).unwrap();
        assert_eq!(library.schema_version().unwrap(), 1);
        assert_eq!(library.count_media().unwrap(), 0);
    }
    let _ = std::fs::remove_file(&path);
}

#[test]
fn sources_are_upserted_not_duplicated() {
    let library = Library::open_in_memory().unwrap();
    library
        .upsert_source("local", SourceKind::Local, "本机影片", "/Movies", 1)
        .unwrap();
    library
        .upsert_source("local", SourceKind::Local, "改过的名字", "/Movies", 1)
        .unwrap();
    assert_eq!(library.source_count().unwrap(), 1);
}

#[test]
fn rescanning_updates_display_fields_but_keeps_first_added_time() {
    let mut library = Library::open_in_memory().unwrap();
    library
        .upsert_source("local", SourceKind::Local, "本机影片", "/Movies", 1)
        .unwrap();
    let first = entry("local", "Dune.mkv", "Dune", 1_000);
    library.upsert_media(std::slice::from_ref(&first)).unwrap();

    let mut second = first.clone();
    second.title = "Dune Part Two".to_string();
    second.added_at_ms = 9_000;
    library.upsert_media(&[second]).unwrap();

    assert_eq!(library.count_media().unwrap(), 1);
    let stored = library.media_by_id(first.id).unwrap().unwrap();
    assert_eq!(stored.title, "Dune Part Two");
    assert_eq!(stored.added_at_ms, 1_000);
}

#[test]
fn existing_ids_reports_what_a_source_already_has() {
    let mut library = Library::open_in_memory().unwrap();
    library
        .upsert_source("local", SourceKind::Local, "本机影片", "/Movies", 1)
        .unwrap();
    let a = entry("local", "a.mkv", "A", 1);
    let b = entry("local", "b.mkv", "B", 2);
    library.upsert_media(std::slice::from_ref(&a)).unwrap();

    let ids = library.existing_ids("local").unwrap();
    assert!(ids.contains(&a.id));
    assert!(!ids.contains(&b.id));
    assert!(library.existing_ids("other").unwrap().is_empty());
}

#[test]
fn deleting_a_source_removes_its_media_but_keeps_watch_state() {
    let path = temp_db("cascade");
    let _ = std::fs::remove_file(&path);
    let media = entry("local", "Dune.mkv", "Dune", 1);
    {
        let mut library = Library::open(&path).unwrap();
        library
            .upsert_source("local", SourceKind::Local, "本机影片", "/Movies", 1)
            .unwrap();
        library.upsert_media(std::slice::from_ref(&media)).unwrap();
        // watch_state 是 T-07 的接口；这里用 SQL 直接写，专门验证它**没有**外键。
        let conn = Connection::open(&path).unwrap();
        conn.execute(
            "INSERT INTO watch_state (media_id, favorite, watched, position_ms, updated_at_ms)
             VALUES (?1, 1, 0, 120000, 5)",
            [media.id.to_string()],
        )
        .unwrap();
    }
    {
        let library = Library::open(&path).unwrap();
        library.delete_source("local").unwrap();
        assert_eq!(library.count_media().unwrap(), 0);
        assert_eq!(library.source_count().unwrap(), 0);
    }
    let conn = Connection::open(&path).unwrap();
    let remaining: i64 = conn
        .query_row("SELECT COUNT(*) FROM watch_state", [], |row| row.get(0))
        .unwrap();
    assert_eq!(remaining, 1, "收藏与进度必须按稳定 ID 保留");
    drop(conn);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn unknown_kind_is_read_as_other_instead_of_failing() {
    let path = temp_db("unknown-kind");
    let _ = std::fs::remove_file(&path);
    {
        let mut library = Library::open(&path).unwrap();
        library
            .upsert_source("local", SourceKind::Local, "本机影片", "/Movies", 1)
            .unwrap();
        library
            .upsert_media(&[entry("local", "a.mkv", "A", 1)])
            .unwrap();
    }
    {
        let conn = Connection::open(&path).unwrap();
        conn.execute("UPDATE media SET kind = 'tv'", []).unwrap();
    }
    let library = Library::open(&path).unwrap();
    let all = library.all_media().unwrap();
    assert_eq!(all.len(), 1);
    assert_eq!(all[0].kind, MediaKind::Other);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_newer_schema_version_is_refused_with_a_readable_error() {
    let path = temp_db("future");
    let _ = std::fs::remove_file(&path);
    {
        let conn = Connection::open(&path).unwrap();
        conn.pragma_update(None, "user_version", 99).unwrap();
    }
    let err = Library::open(&path).unwrap_err();
    assert_eq!(err.kind(), "db");
    assert!(err.to_string().contains("99"));
    let _ = std::fs::remove_file(&path);
}
