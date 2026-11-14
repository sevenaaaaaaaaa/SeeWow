//! T-15 验收：片头片尾标记的落盘、覆盖、清空与 v1→v2 迁移。

use std::path::PathBuf;

use seewow_library::{ChapterKind, ChapterMark, Library};

fn temp_db(name: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "seewow-chapters-{name}-{}-{}.db",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let _ = std::fs::remove_file(&path);
    path
}

#[test]
fn marks_are_written_read_and_overwritten() {
    let library = Library::open_in_memory().unwrap();
    assert_eq!(
        library
            .chapter_mark("怪奇物语", ChapterKind::IntroEnd)
            .unwrap(),
        None
    );

    library
        .set_chapter_mark("怪奇物语", ChapterKind::IntroEnd, 80_000, 1)
        .unwrap();
    let mark = library
        .chapter_mark("怪奇物语", ChapterKind::IntroEnd)
        .unwrap()
        .expect("读过一次就该有");
    assert_eq!(mark.position_ms, 80_000);
    assert_eq!(mark.updated_at_ms, 1);

    // 同一 kind 再写一次是覆盖，不是插入两行。
    library
        .set_chapter_mark("怪奇物语", ChapterKind::IntroEnd, 95_000, 2)
        .unwrap();
    let marks = library.chapter_marks("怪奇物语").unwrap();
    assert_eq!(marks.len(), 1);
    assert_eq!(marks[0].position_ms, 95_000);
}

#[test]
fn both_kinds_sort_by_time_and_clear_together() {
    let library = Library::open_in_memory().unwrap();
    library
        .set_chapter_mark("Dark", ChapterKind::OutroStart, 2_500_000, 1)
        .unwrap();
    library
        .set_chapter_mark("Dark", ChapterKind::IntroEnd, 85_000, 1)
        .unwrap();

    let marks = library.chapter_marks("Dark").unwrap();
    assert_eq!(marks.len(), 2);
    assert_eq!(marks[0].kind, ChapterKind::IntroEnd);
    assert_eq!(marks[1].kind, ChapterKind::OutroStart);

    assert_eq!(library.clear_chapter_marks("Dark").unwrap(), 2);
    assert!(library.chapter_marks("Dark").unwrap().is_empty());
    // 别的剧不受影响。
    library
        .set_chapter_mark("Friends", ChapterKind::IntroEnd, 60_000, 1)
        .unwrap();
    library.clear_chapter_marks("Dark").unwrap();
    assert_eq!(library.chapter_marks("Friends").unwrap().len(), 1);
}

#[test]
fn negative_positions_are_clamped_to_zero() {
    let library = Library::open_in_memory().unwrap();
    library
        .set_chapter_mark("Dark", ChapterKind::IntroEnd, -5_000, 1)
        .unwrap();
    let mark: ChapterMark = library
        .chapter_mark("Dark", ChapterKind::IntroEnd)
        .unwrap()
        .unwrap();
    assert_eq!(mark.position_ms, 0);
}

#[test]
fn marks_survive_reopening_the_file() {
    let path = temp_db("reopen");
    {
        let library = Library::open(&path).unwrap();
        library
            .set_chapter_mark("蓝色星球", ChapterKind::OutroStart, 3_000_000, 7)
            .unwrap();
    }
    let reopened = Library::open(&path).unwrap();
    let mark = reopened
        .chapter_mark("蓝色星球", ChapterKind::OutroStart)
        .unwrap()
        .unwrap();
    assert_eq!(mark.position_ms, 3_000_000);
    assert_eq!(mark.updated_at_ms, 7);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn opening_an_old_v1_database_migrates_to_v2() {
    let path = temp_db("migrate");
    // 手搓一个 v1 库：只有 user_version=1 和 v1 的表，没有 chapter_marks。
    {
        let conn = rusqlite::Connection::open(&path).unwrap();
        conn.execute_batch(seewow_library::schema::V1).unwrap();
        conn.pragma_update(None, "user_version", 1).unwrap();
    }
    let library = Library::open(&path).unwrap();
    assert_eq!(library.schema_version().unwrap(), 2);
    library
        .set_chapter_mark("Dark", ChapterKind::IntroEnd, 42_000, 1)
        .unwrap();
    assert_eq!(library.chapter_marks("Dark").unwrap().len(), 1);
    let _ = std::fs::remove_file(&path);
}
