//! T-06 验收：关键词、筛选、排序与分页。

use std::path::PathBuf;

use seewow_core::{MediaEntry, MediaId, MediaKind, SourceKind};
use seewow_library::{Library, Query, SortBy};

struct Seed<'a> {
    path: &'a str,
    title: &'a str,
    kind: MediaKind,
    year: Option<i32>,
    quality: &'a str,
    show: Option<&'a str>,
    added_at_ms: i64,
}

fn media(seed: Seed<'_>) -> MediaEntry {
    MediaEntry {
        id: MediaId::from_parts("local", seed.path),
        source_id: "local".to_string(),
        relative_path: PathBuf::from(seed.path),
        kind: seed.kind,
        title: seed.title.to_string(),
        show_title: seed.show.map(str::to_string),
        year: seed.year,
        season: None,
        episode: None,
        quality: seed.quality.to_string(),
        added_at_ms: seed.added_at_ms,
    }
}

fn seeded() -> Library {
    let mut library = Library::open_in_memory().unwrap();
    library
        .upsert_source("local", SourceKind::Local, "本机影片", "/Movies", 1)
        .unwrap();
    library
        .upsert_media(&[
            media(Seed {
                path: "a.mkv",
                title: "Alpha",
                kind: MediaKind::Movie,
                year: Some(2020),
                quality: "4K",
                show: None,
                added_at_ms: 100,
            }),
            media(Seed {
                path: "b.mkv",
                title: "beta",
                kind: MediaKind::Movie,
                year: Some(2021),
                quality: "1080p",
                show: None,
                added_at_ms: 200,
            }),
            media(Seed {
                path: "c.mkv",
                title: "Gamma S01E01",
                kind: MediaKind::Episode,
                year: None,
                quality: "4K",
                show: Some("Gamma"),
                added_at_ms: 300,
            }),
            media(Seed {
                path: "d.mkv",
                title: "100%_real",
                kind: MediaKind::Movie,
                year: Some(2022),
                quality: "",
                show: None,
                added_at_ms: 400,
            }),
            media(Seed {
                path: "e.mkv",
                title: "No Year",
                kind: MediaKind::Movie,
                year: None,
                quality: "",
                show: None,
                added_at_ms: 50,
            }),
        ])
        .unwrap();
    library
}

fn titles(entries: &[MediaEntry]) -> Vec<&str> {
    entries.iter().map(|entry| entry.title.as_str()).collect()
}

#[test]
fn keyword_matches_title_and_show_title_ignoring_case() {
    let library = seeded();
    let by_show = library
        .search(&Query {
            text: Some("gamma".to_string()),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(titles(&by_show), ["Gamma S01E01"]);

    let by_upper = library
        .search(&Query {
            text: Some("ALPHA".to_string()),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(titles(&by_upper), ["Alpha"]);
}

#[test]
fn like_wildcards_are_literal() {
    let library = seeded();
    let percent = library
        .search(&Query {
            text: Some("100%_".to_string()),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(titles(&percent), ["100%_real"]);

    // 单独一个 "%" 不能变成「匹配所有」。
    let lone = library
        .search(&Query {
            text: Some("%".to_string()),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(titles(&lone), ["100%_real"]);
}

#[test]
fn filters_combine() {
    let library = seeded();
    let episodes = library
        .search(&Query {
            kind: Some(MediaKind::Episode),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(titles(&episodes), ["Gamma S01E01"]);

    let year = library
        .search(&Query {
            year: Some(2021),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(titles(&year), ["beta"]);

    let four_k = library
        .search(&Query {
            quality: Some("4K".to_string()),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(four_k.len(), 2);

    let four_k_movies = library
        .search(&Query {
            quality: Some("4K".to_string()),
            kind: Some(MediaKind::Movie),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(titles(&four_k_movies), ["Alpha"]);
}

#[test]
fn sorting_is_deterministic() {
    let library = seeded();

    let by_title = library
        .search(&Query {
            sort: SortBy::TitleAsc,
            ..Query::default()
        })
        .unwrap();
    assert_eq!(
        titles(&by_title),
        ["100%_real", "Alpha", "beta", "Gamma S01E01", "No Year"]
    );

    let by_year = library
        .search(&Query {
            sort: SortBy::YearDesc,
            ..Query::default()
        })
        .unwrap();
    assert_eq!(
        titles(&by_year),
        ["100%_real", "beta", "Alpha", "Gamma S01E01", "No Year"]
    );

    let by_added = library.search(&Query::default()).unwrap();
    assert_eq!(titles(&by_added).first().copied(), Some("100%_real"));
}

#[test]
fn paging_covers_every_row_exactly_once() {
    let library = seeded();
    let full = library
        .search(&Query {
            sort: SortBy::TitleAsc,
            ..Query::default()
        })
        .unwrap();
    let mut paged = Vec::new();
    for offset in (0..full.len()).step_by(2) {
        let page = library
            .search(
                &Query {
                    sort: SortBy::TitleAsc,
                    ..Query::default()
                }
                .page(2, offset),
            )
            .unwrap();
        paged.extend(page);
    }
    assert_eq!(titles(&paged), titles(&full));
    assert_eq!(library.search_count(&Query::default()).unwrap(), 5);
}

#[test]
fn zero_limit_falls_back_and_offset_past_end_is_empty() {
    let library = seeded();
    let all = library
        .search(&Query {
            limit: 0,
            ..Query::default()
        })
        .unwrap();
    assert_eq!(all.len(), 5);

    let past_end = library.search(&Query::default().page(10, 99)).unwrap();
    assert!(past_end.is_empty());
    assert_eq!(library.search_count(&Query::default()).unwrap(), 5);
}

#[test]
fn an_empty_keyword_is_ignored_not_matched_against_nothing() {
    let library = seeded();
    let all = library
        .search(&Query {
            text: Some("   ".to_string()),
            ..Query::default()
        })
        .unwrap();
    assert_eq!(all.len(), 5);
}
