//! T-15 验收（红先）：播放页接线的可验证部分。
//!
//! 覆盖四件事，对应 plan §3.6 的 T-15 DoD：
//! 1. 上次位置接续（用已有 `ResumePolicy`，不另立门槛）；
//! 2. 片头片尾标记按剧集读取，重开片库仍在；
//! 3. 字幕轨菜单来自 mpv `track-list`（这里用 `TrackInfo` 直接构造，等价于快照）；
//! 4. 进度落盘节流与看完清空。
//!
//! 这些都是决定层，不进窗口：真机起播证据在 `playback_smoke.rs`（`SEEWOW_MPV_TEST=1`）。

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use seewow_app::playback::{
    ChapterPlan, MediaKey, SessionState, StartReason, flush_progress, load_chapter_plan,
    media_key_for, next_subtitle, persist_progress, plan_start, should_prompt_outro, subtitle_menu,
    watch_state_of,
};
use seewow_core::{MediaEntry, MediaId, MediaKind, ResumePolicy, TrackInfo};
use seewow_library::WatchState;
use seewow_library::{ChapterKind, Library};

const MINUTE: i64 = 60_000;

fn temp_db(tag: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "seewow-playback-{tag}-{}-{}.db",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let _ = std::fs::remove_file(&path);
    path
}

fn episode(relative: &str, show: &str, season: u32, episode: u32) -> MediaEntry {
    MediaEntry {
        id: MediaId::from_parts("local", relative),
        source_id: "local".to_string(),
        relative_path: PathBuf::from(relative),
        kind: MediaKind::Episode,
        title: format!("{show} S{season:02}E{episode:02}"),
        show_title: Some(show.to_string()),
        year: Some(2017),
        season: Some(season),
        episode: Some(episode),
        quality: "1080p".to_string(),
        added_at_ms: 1,
    }
}

fn movie(relative: &str, title: &str) -> MediaEntry {
    MediaEntry {
        id: MediaId::from_parts("local", relative),
        source_id: "local".to_string(),
        relative_path: PathBuf::from(relative),
        kind: MediaKind::Movie,
        title: title.to_string(),
        show_title: None,
        year: Some(2021),
        season: None,
        episode: None,
        quality: "1080p".to_string(),
        added_at_ms: 1,
    }
}

fn stored(position_ms: i64, duration_ms: i64) -> WatchState {
    WatchState {
        favorite: false,
        watched: false,
        position_ms,
        duration_ms: Some(duration_ms),
        updated_at_ms: 7,
    }
}

// ---------------------------------------------------------------- 起播点

#[test]
fn a_file_never_watched_starts_from_zero() {
    let policy = ResumePolicy::default();
    let plan = plan_start(&policy, None, Some(45 * MINUTE), &ChapterPlan::default());
    assert_eq!(plan.start_ms, 0);
    assert_eq!(plan.reason, StartReason::FromStart);
}

#[test]
fn resume_rewinds_three_seconds_from_the_stored_position() {
    let policy = ResumePolicy::default();
    let watch = stored(10 * MINUTE, 45 * MINUTE);
    let plan = plan_start(
        &policy,
        Some(&watch),
        Some(45 * MINUTE),
        &ChapterPlan::default(),
    );
    assert_eq!(plan.start_ms, 10 * MINUTE - 3_000);
    assert_eq!(plan.reason, StartReason::Resumed);
}

#[test]
fn progress_below_the_thirty_second_gate_starts_from_zero() {
    let policy = ResumePolicy::default();
    let watch = stored(29_999, 45 * MINUTE);
    let plan = plan_start(
        &policy,
        Some(&watch),
        Some(45 * MINUTE),
        &ChapterPlan::default(),
    );
    assert_eq!(plan.start_ms, 0);
    assert_eq!(plan.reason, StartReason::FromStart);
}

#[test]
fn a_watched_file_starts_over_and_says_so() {
    let policy = ResumePolicy::default();
    let watch = stored(44 * MINUTE, 45 * MINUTE);
    let plan = plan_start(
        &policy,
        Some(&watch),
        Some(45 * MINUTE),
        &ChapterPlan::default(),
    );
    assert_eq!(plan.start_ms, 0);
    assert_eq!(plan.reason, StartReason::Finished);
}

// ---------------------------------------------------------------- 片头片尾

fn marks(intro: Option<i64>, outro: Option<i64>) -> ChapterPlan {
    ChapterPlan {
        intro_end_ms: intro,
        outro_start_ms: outro,
    }
}

#[test]
fn intro_is_skipped_when_the_start_lands_inside_it() {
    let policy = ResumePolicy::default();
    let chapters = marks(Some(80_000), Some(2_500_000));

    // 从头播也跳片头：连看下一集时不必每次手动拖。
    let fresh = plan_start(&policy, None, Some(45 * MINUTE), &chapters);
    assert_eq!(fresh.start_ms, 80_000);
    assert_eq!(fresh.reason, StartReason::IntroSkipped);

    // 续播点仍在片头里：同样跳到片头结束。
    let early = stored(30_000, 45 * MINUTE);
    let resumed = plan_start(&policy, Some(&early), Some(45 * MINUTE), &chapters);
    assert_eq!(resumed.start_ms, 80_000);
    assert_eq!(resumed.reason, StartReason::IntroSkipped);
}

#[test]
fn a_resume_point_past_the_intro_is_kept_as_is() {
    let policy = ResumePolicy::default();
    let chapters = marks(Some(80_000), None);
    let watch = stored(10 * MINUTE, 45 * MINUTE);
    let plan = plan_start(&policy, Some(&watch), Some(45 * MINUTE), &chapters);
    // 10:00 续播，默认回退 3 秒，且已经越过 80 秒片头，不再跳片头。
    assert_eq!(plan.start_ms, 10 * MINUTE - policy.rewind_ms);
    assert_eq!(plan.reason, StartReason::Resumed);
}

#[test]
fn nonsense_intro_marks_are_ignored_instead_of_breaking_playback() {
    let policy = ResumePolicy::default();
    // 片头比片子还长：丢掉这条标记，从头播。
    let too_long = plan_start(&policy, None, Some(90_000), &marks(Some(100_000), None));
    assert_eq!(too_long.start_ms, 0);
    assert_eq!(too_long.reason, StartReason::FromStart);

    // 0 / 负值同样丢掉。
    let zero = plan_start(&policy, None, Some(45 * MINUTE), &marks(Some(0), None));
    assert_eq!(zero.start_ms, 0);
    let negative = plan_start(&policy, None, Some(45 * MINUTE), &marks(Some(-5_000), None));
    assert_eq!(negative.start_ms, 0);
}

#[test]
fn outro_prompts_once_when_the_tail_is_reached() {
    let chapters = marks(None, Some(2_500_000));
    assert!(!should_prompt_outro(2_499_999, &chapters, false));
    assert!(should_prompt_outro(2_500_000, &chapters, false));
    // 同一个位置只提示一次：用户已经看到过就别反复弹。
    assert!(!should_prompt_outro(2_600_000, &chapters, true));
    // 没标记：永远不提示。
    assert!(!should_prompt_outro(
        2_600_000,
        &ChapterPlan::default(),
        false
    ));
}

// ---------------------------------------------------------------- 片库往返

#[test]
fn marks_are_read_by_show_key_and_survive_reopening_the_file() {
    let path = temp_db("reopen");

    {
        let library = Library::open(&path).unwrap();
        library
            .set_chapter_mark("dark", ChapterKind::IntroEnd, 85_000, 1)
            .unwrap();
        library
            .set_chapter_mark("dark", ChapterKind::OutroStart, 2_500_000, 1)
            .unwrap();
        let loaded = load_chapter_plan(&library, Some("dark"));
        assert_eq!(loaded, marks(Some(85_000), Some(2_500_000)));
    }

    // 重开片库：标记还在，而且能直接喂给起播决策。
    let reopened = Library::open(&path).unwrap();
    let chapters = load_chapter_plan(&reopened, Some("dark"));
    assert_eq!(chapters, marks(Some(85_000), Some(2_500_000)));

    let watch = stored(10 * MINUTE, 45 * MINUTE);
    let plan = plan_start(
        &ResumePolicy::default(),
        Some(&watch),
        Some(45 * MINUTE),
        &chapters,
    );
    assert_eq!(plan.start_ms, 10 * MINUTE - 3_000);

    let _ = std::fs::remove_file(&path);
}

#[test]
fn marks_of_another_show_do_not_leak_in() {
    let library = Library::open_in_memory().unwrap();
    library
        .set_chapter_mark("dark", ChapterKind::IntroEnd, 85_000, 1)
        .unwrap();
    assert_eq!(
        load_chapter_plan(&library, Some("friends")),
        ChapterPlan::default()
    );
    // 没有 show_key（电影、或没扫进库的文件）就是空计划，不报错。
    assert_eq!(load_chapter_plan(&library, None), ChapterPlan::default());
}

// ---------------------------------------------------------------- 认条目 / show_key

#[test]
fn a_scanned_entry_is_matched_by_path_suffix() {
    let entries = vec![
        movie("Movies/Dune.mkv", "Dune"),
        episode("Shows/Dark/S01E01.mkv", "Dark", 1, 1),
    ];
    let key = media_key_for(Path::new("/Volumes/Media/Shows/Dark/S01E01.mkv"), &entries);
    assert_eq!(key.id, entries[1].id);
    assert_eq!(key.show_key.as_deref(), Some("dark"));

    // 电影没有 show_key：片头片尾按剧存，电影不参与。
    let film = media_key_for(Path::new("/Volumes/Media/Movies/Dune.mkv"), &entries);
    assert_eq!(film.id, entries[0].id);
    assert_eq!(film.show_key, None);
}

#[test]
fn an_unscanned_file_still_gets_a_stable_key() {
    let entries = vec![movie("Movies/Dune.mkv", "Dune")];
    let key = media_key_for(Path::new("/tmp/elsewhere/clip.mkv"), &entries);
    assert_eq!(
        key.id,
        MediaId::from_parts("local", "/tmp/elsewhere/clip.mkv")
    );
    assert_eq!(key.show_key, None);
    // 同一个路径两次给出同一个键：重启后还能接上。
    assert_eq!(
        key,
        media_key_for(Path::new("/tmp/elsewhere/clip.mkv"), &entries)
    );
}

#[test]
fn show_key_is_normalised_so_the_same_show_always_matches() {
    let mut entry = episode("Shows/X/S02E03.mkv", "  The   Office ", 2, 3);
    let key = media_key_for(
        Path::new("/nowhere/The Office S02E03.mkv"),
        std::slice::from_ref(&entry),
    );
    assert_eq!(key.show_key.as_deref(), Some("the office"));

    // 空剧名不能变成空键（否则所有空剧名会共用一条标记）。
    entry.show_title = None;
    assert_eq!(
        media_key_for(Path::new("/x.mkv"), &[entry.clone()]).show_key,
        None
    );
}

// ---------------------------------------------------------------- 字幕轨

#[test]
fn subtitle_menu_comes_from_the_mpv_track_list() {
    let tracks = vec![
        TrackInfo {
            id: 1,
            language: Some("zh-Hans".to_string()),
            title: Some("简体中文".to_string()),
        },
        TrackInfo {
            id: 2,
            language: Some("en".to_string()),
            title: None,
        },
    ];
    let menu = subtitle_menu(&tracks, Some(2));
    assert_eq!(menu.items.len(), 2);
    assert_eq!(menu.items[0].label, "简体中文");
    assert_eq!(menu.items[1].label, "en");
    assert_eq!(menu.selected, Some(2));
    assert_eq!(menu.summary, "CC 2/2");

    let empty = subtitle_menu(&[], None);
    assert!(empty.items.is_empty());
    assert_eq!(empty.summary, "CC 关");
}

#[test]
fn subtitle_cycle_walks_every_track_then_turns_off() {
    let tracks = vec![
        TrackInfo {
            id: 3,
            language: Some("zh".to_string()),
            title: None,
        },
        TrackInfo {
            id: 7,
            language: None,
            title: None,
        },
    ];
    assert_eq!(next_subtitle(&tracks, None), Some(3));
    assert_eq!(next_subtitle(&tracks, Some(3)), Some(7));
    assert_eq!(next_subtitle(&tracks, Some(7)), None);
    // 选中的是一条已经消失的轨（换片之后）：从第一条重新开始，不卡死。
    assert_eq!(next_subtitle(&tracks, Some(99)), Some(3));
    assert_eq!(next_subtitle(&[], None), None);
}

// ---------------------------------------------------------------- 进度落盘

#[test]
fn progress_is_throttled_and_cleared_when_watched() {
    let library = Library::open_in_memory().unwrap();
    let id = MediaId::from_parts("local", "Shows/Dark/S01E01.mkv");
    let policy = ResumePolicy::default();

    // 前进不足 10 秒：不写。
    let unchanged =
        persist_progress(&library, id, 25_000, Some(45 * MINUTE), &policy, 20_000, 1).unwrap();
    assert_eq!(unchanged, 20_000);
    assert_eq!(watch_state_of(&library, id).position_ms, 0);

    // 前进够 10 秒：写一次。
    let written =
        persist_progress(&library, id, 30_000, Some(45 * MINUTE), &policy, 20_000, 2).unwrap();
    assert_eq!(written, 30_000);
    let watch = watch_state_of(&library, id);
    assert_eq!(watch.position_ms, 30_000);
    assert_eq!(watch.duration_ms, Some(45 * MINUTE));

    // 往回拖立刻写。
    let rewound =
        persist_progress(&library, id, 5_000, Some(45 * MINUTE), &policy, 30_000, 3).unwrap();
    assert_eq!(rewound, 5_000);

    // 关窗 flush：看完写 0（下次从头）。
    flush_progress(&library, id, 44 * MINUTE, Some(45 * MINUTE), &policy, 4).unwrap();
    assert_eq!(watch_state_of(&library, id).position_ms, 0);
}

#[test]
fn session_state_carries_the_resume_decision_for_a_reopened_file() {
    let path = temp_db("session");
    let entries = vec![episode("Shows/Dark/S01E01.mkv", "Dark", 1, 1)];
    let key: MediaKey = media_key_for(Path::new("/media/Shows/Dark/S01E01.mkv"), &entries);

    {
        let library = Library::open(&path).unwrap();
        library
            .set_chapter_mark("dark", ChapterKind::IntroEnd, 85_000, 1)
            .unwrap();
        library
            .set_progress(key.id, 10 * MINUTE, Some(45 * MINUTE), 1)
            .unwrap();
    }

    // 「重开」：新进程读同一个库，状态直接进会话。
    let reopened = Library::open(&path).unwrap();
    let chapters = load_chapter_plan(&reopened, key.show_key.as_deref());
    let session = SessionState::begin(&reopened, key, chapters);

    let plan = session.plan(&ResumePolicy::default(), Some(45 * MINUTE));
    assert_eq!(plan.start_ms, 10 * MINUTE - 3_000);
    assert_eq!(plan.reason, StartReason::Resumed);
    // 会话把「该续播的原始位置」也带着，便于 flush 时写回真实进度。
    assert_eq!(session.stored.position_ms, 10 * MINUTE);

    let _ = std::fs::remove_file(&path);
}
