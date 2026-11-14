//! T-07 验收：收藏、看过、进度，以及片源移除后的状态保留。

use std::path::PathBuf;

use seewow_core::{MediaEntry, MediaId, MediaKind, SourceKind};
use seewow_library::Library;

fn entry(source: &str, path: &str, title: &str) -> MediaEntry {
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
        quality: String::new(),
        added_at_ms: 1,
    }
}

fn seeded() -> (Library, MediaEntry) {
    let mut library = Library::open_in_memory().unwrap();
    library
        .upsert_source("local", SourceKind::Local, "本机影片", "/Movies", 1)
        .unwrap();
    let media = entry("local", "Dune.mkv", "Dune");
    library.upsert_media(std::slice::from_ref(&media)).unwrap();
    (library, media)
}

#[test]
fn untouched_media_has_no_state_row() {
    let (library, media) = seeded();
    assert!(library.watch_state(media.id).unwrap().is_none());
    assert!(library.favorites(10).unwrap().is_empty());
    assert!(library.in_progress(10).unwrap().is_empty());
}

#[test]
fn marking_a_favorite_does_not_clear_progress() {
    let (library, media) = seeded();
    library
        .set_progress(media.id, 120_000, Some(600_000), 10)
        .unwrap();
    library.set_favorite(media.id, true, 20).unwrap();

    let state = library.watch_state(media.id).unwrap().unwrap();
    assert!(state.favorite);
    assert_eq!(state.position_ms, 120_000);
    assert_eq!(state.duration_ms, Some(600_000));
    assert_eq!(state.updated_at_ms, 20);
}

#[test]
fn progress_is_idempotent_and_clamped_to_duration() {
    let (library, media) = seeded();
    library
        .set_progress(media.id, 5_000, Some(60_000), 1)
        .unwrap();
    library
        .set_progress(media.id, 5_000, Some(60_000), 2)
        .unwrap();
    let state = library.watch_state(media.id).unwrap().unwrap();
    assert_eq!(state.position_ms, 5_000);
    assert_eq!(state.updated_at_ms, 2);

    library
        .set_progress(media.id, 90_000, Some(60_000), 3)
        .unwrap();
    assert_eq!(
        library.watch_state(media.id).unwrap().unwrap().position_ms,
        60_000
    );

    // 只报位置时保留原有总时长。
    library.set_progress(media.id, 30_000, None, 4).unwrap();
    let state = library.watch_state(media.id).unwrap().unwrap();
    assert_eq!(state.position_ms, 30_000);
    assert_eq!(state.duration_ms, Some(60_000));
}

#[test]
fn negative_progress_is_rejected() {
    let (library, media) = seeded();
    let err = library.set_progress(media.id, -1, None, 1).unwrap_err();
    assert_eq!(err.kind(), "parse");
    let err = library.set_progress(media.id, 1, Some(-5), 1).unwrap_err();
    assert_eq!(err.kind(), "parse");
}

#[test]
fn favorites_are_ordered_by_last_action() {
    let (mut library, first) = seeded();
    let second = entry("local", "Arrival.mkv", "Arrival");
    library.upsert_media(std::slice::from_ref(&second)).unwrap();

    let favorites = |library: &Library| -> Vec<String> {
        library
            .favorites(10)
            .unwrap()
            .into_iter()
            .map(|entry| entry.title)
            .collect()
    };

    library.set_favorite(first.id, true, 100).unwrap();
    library.set_favorite(second.id, true, 200).unwrap();
    assert_eq!(favorites(&library), ["Arrival", "Dune"]);

    library.set_favorite(first.id, true, 300).unwrap();
    assert_eq!(favorites(&library), ["Dune", "Arrival"]);

    library.set_favorite(first.id, false, 400).unwrap();
    assert_eq!(favorites(&library), ["Arrival"]);
}

#[test]
fn in_progress_lists_started_unwatched_media_only() {
    let (mut library, first) = seeded();
    let second = entry("local", "Arrival.mkv", "Arrival");
    library.upsert_media(std::slice::from_ref(&second)).unwrap();

    library.set_progress(first.id, 10_000, None, 1).unwrap();
    library.set_progress(second.id, 20_000, None, 2).unwrap();
    library.set_watched(second.id, true, 3).unwrap();

    let titles: Vec<String> = library
        .in_progress(10)
        .unwrap()
        .into_iter()
        .map(|entry| entry.title)
        .collect();
    assert_eq!(titles, ["Dune"]);
}

#[test]
fn state_survives_source_removal_and_reattaches_on_rescan() {
    let (mut library, media) = seeded();
    library.set_favorite(media.id, true, 7).unwrap();

    library.delete_source("local").unwrap();
    assert!(library.media_by_id(media.id).unwrap().is_none());
    assert!(
        library.watch_state(media.id).unwrap().is_some(),
        "收藏必须按稳定 ID 保留"
    );
    assert!(library.favorites(10).unwrap().is_empty());

    library
        .upsert_source("local", SourceKind::Local, "本机影片", "/Movies", 1)
        .unwrap();
    library.upsert_media(std::slice::from_ref(&media)).unwrap();
    assert_eq!(library.favorites(10).unwrap().len(), 1);
    assert!(library.favorites(10).unwrap()[0].title == "Dune");
}
