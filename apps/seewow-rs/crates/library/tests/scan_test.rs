//! T-05 验收：递归、过滤、增量、符号链接与失败恢复。

use std::path::{Path, PathBuf};

use seewow_core::{MediaId, MediaKind};
use seewow_library::{Library, ScanOptions, collect_media, scan_into_library};

fn temp_root(tag: &str) -> PathBuf {
    let root = std::env::temp_dir().join(format!("seewow-scan-{}-{tag}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).unwrap();
    root
}

fn touch(root: &Path, relative: &str) {
    let path = root.join(relative);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, b"test").unwrap();
}

fn seed_tree(root: &Path) {
    touch(root, "Movies/Dune Part Two (2024) 2160p.mkv");
    touch(root, "Shows/Dark/Dark S01E02 1080p.mkv");
    touch(root, "Shows/Dark/S01E03.mkv");
    touch(root, "notes.txt");
    touch(root, ".hidden/Secret 2020.mkv");
}

#[test]
fn walks_recursively_and_parses_names() {
    let root = temp_root("walk");
    seed_tree(&root);

    let (entries, report) = collect_media(&root, "local", &ScanOptions::default());
    assert_eq!(report.failures, Vec::new());
    assert_eq!(entries.len(), 3, "只收视频文件，隐藏目录与非视频跳过");

    let dune = entries
        .iter()
        .find(|entry| entry.title.starts_with("Dune"))
        .unwrap();
    assert_eq!(dune.year, Some(2024));
    assert_eq!(dune.kind, MediaKind::Movie);
    assert_eq!(
        dune.relative_path,
        PathBuf::from("Movies/Dune Part Two (2024) 2160p.mkv")
    );
    assert_eq!(
        dune.id,
        MediaId::from_parts("local", &dune.relative_path.to_string_lossy())
    );

    let episode = entries
        .iter()
        .find(|entry| entry.relative_path.ends_with("Dark S01E02 1080p.mkv"))
        .unwrap();
    assert_eq!(episode.kind, MediaKind::Episode);
    assert_eq!((episode.season, episode.episode), (Some(1), Some(2)));
    assert_eq!(episode.show_title.as_deref(), Some("Dark"));

    // 裸 S01E03.mkv 的剧名来自父目录（D-04 的刻意偏差）。
    let bare = entries
        .iter()
        .find(|entry| entry.relative_path.ends_with("S01E03.mkv"))
        .unwrap();
    assert_eq!(bare.title, "Dark  S01E03");

    assert!(report.skipped >= 2);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn hidden_folders_are_included_when_asked() {
    let root = temp_root("hidden");
    seed_tree(&root);
    let options = ScanOptions {
        include_hidden: true,
    };
    let (entries, _) = collect_media(&root, "local", &options);
    assert_eq!(entries.len(), 4);
    assert!(
        entries
            .iter()
            .any(|entry| entry.relative_path.starts_with(".hidden"))
    );
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn extensions_are_case_insensitive() {
    let root = temp_root("ext");
    touch(&root, "Mixed Case.MKV");
    touch(&root, "clip.Mp4");
    touch(&root, "song.flac");
    let (entries, _) = collect_media(&root, "local", &ScanOptions::default());
    assert_eq!(entries.len(), 2);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn rescanning_counts_new_entries_only_once() {
    let root = temp_root("incremental");
    seed_tree(&root);
    let mut library = Library::open_in_memory().unwrap();
    library
        .upsert_source(
            "local",
            seewow_core::SourceKind::Local,
            "本机影片",
            root.to_str().unwrap(),
            1,
        )
        .unwrap();

    let first = scan_into_library(&mut library, &root, "local", &ScanOptions::default()).unwrap();
    assert_eq!((first.added, first.updated), (3, 0));
    assert_eq!(library.count_media().unwrap(), 3);

    let second = scan_into_library(&mut library, &root, "local", &ScanOptions::default()).unwrap();
    assert_eq!((second.added, second.updated), (0, 3));
    assert_eq!(library.count_media().unwrap(), 3);
    let _ = std::fs::remove_dir_all(&root);
}

#[cfg(unix)]
#[test]
fn symlinks_are_not_followed() {
    use std::os::unix::fs::symlink;

    let root = temp_root("symlink");
    touch(&root, "real/Movie 2020.mkv");
    symlink(root.join("real"), root.join("link")).unwrap();

    let (entries, report) = collect_media(&root, "local", &ScanOptions::default());
    assert_eq!(entries.len(), 1, "符号链接目录不能被跟随，否则会重复收录");
    assert!(report.skipped >= 1);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_missing_root_is_reported_not_a_panic() {
    let root = temp_root("missing");
    let missing = root.join("does-not-exist");
    let (entries, report) = collect_media(&missing, "local", &ScanOptions::default());
    assert!(entries.is_empty());
    assert_eq!(report.failures.len(), 1);
    assert_eq!(report.failures[0].path, missing);
    let _ = std::fs::remove_dir_all(&root);
}
