//! T-15 真机（无窗口）冒烟：起播决策真的能落到 mpv 上。
//!
//! 默认跳过（CI 没有视频文件）。样片用 ffmpeg 生成：
//!   ffmpeg -f lavfi -i testsrc=size=320x180:rate=30 -f lavfi -i sine=frequency=440 \
//!     -t 1 -c:v libx264 -pix_fmt yuv420p -c:a aac clips/t15.mkv
//! 跑：
//!   SEEWOW_MPV_TEST=1 SEEWOW_MPV_SAMPLE=/path/clip.mkv \
//!     cargo test -p seewow-app --test playback_smoke -- --nocapture --test-threads=1
//!
//! 这里用的是 `plan_start` 的真结论（不是手写的位置），所以「续播回退 3 秒」和
//! 「跳过片头」两条 DoD 的落点都有 mpv 的 `time-pos` 作证据。

use std::path::PathBuf;
use std::time::{Duration, Instant};

use seewow_app::playback::{ChapterPlan, media_key_for, plan_start};
use seewow_core::ResumePolicy;
use seewow_library::WatchState;
use seewow_library::Library;
use seewow_player::mpv::{Player, PlayerOptions};

fn sample() -> Option<PathBuf> {
    if std::env::var("SEEWOW_MPV_TEST").as_deref() != Ok("1") {
        eprintln!("skip: 未设置 SEEWOW_MPV_TEST=1");
        return None;
    }
    std::env::var("SEEWOW_MPV_SAMPLE")
        .map(PathBuf::from)
        .map_err(|_| eprintln!("skip: 未设置 SEEWOW_MPV_SAMPLE"))
        .ok()
}

fn start() -> Player {
    Player::start(PlayerOptions {
        vo_override: Some("null".to_string()),
        log_file: None,
        logger: None,
    })
    .expect("创建 Player")
}

fn wait_for(
    player: &Player,
    timeout: Duration,
    mut predicate: impl FnMut(&seewow_player::mpv::PlayerSnapshot) -> bool,
) -> Option<seewow_player::mpv::PlayerSnapshot> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if let Some(snapshot) = player.try_snapshot()
            && predicate(&snapshot)
        {
            return Some(snapshot);
        }
        std::thread::sleep(Duration::from_millis(60));
    }
    None
}

/// 1 秒样片用的策略：门槛降到 0.5 秒、回退 0.2 秒，才测得出「回退」这件事。
fn short_clip_policy() -> ResumePolicy {
    ResumePolicy {
        min_resume_ms: 0,
        rewind_ms: 200,
        ..ResumePolicy::default()
    }
}

#[test]
fn resume_seek_lands_where_the_plan_said_it_would() {
    let Some(path) = sample() else { return };
    let library = Library::open_in_memory().unwrap();
    let key = media_key_for(&path, &[]);

    // 上次看到 0.9 秒（1 秒样片的 90%），关门时没算看完。
    library.set_progress(key.id, 900, Some(1_000), 1).unwrap();
    let watch = library.watch_state(key.id).unwrap().unwrap_or(WatchState {
        position_ms: 900,
        duration_ms: Some(1_000),
        ..WatchState::default()
    });
    let plan = plan_start(
        &short_clip_policy(),
        Some(&watch),
        Some(1_000),
        &ChapterPlan::default(),
    );
    eprintln!("plan.start_ms={} reason={:?}", plan.start_ms, plan.reason);
    assert_eq!(plan.start_ms, 700, "续播点应为 900-200");

    let player = start();
    assert!(player.load(&path));
    wait_for(&player, Duration::from_secs(8), |s| s.time_pos.is_some())
        .expect("8 秒内没读到 time-pos");

    assert!(player.seek_absolute(plan.start_ms as f64 / 1000.0));
    let landed = wait_for(&player, Duration::from_secs(4), |s| {
        s.time_pos.is_some_and(|pos| (pos - 0.7).abs() < 0.3)
    })
    .expect("续播 seek 没有落在 0.7s ±300ms");
    eprintln!("续播落点: time-pos={:?}", landed.time_pos);
    player.quit();
}

#[test]
fn intro_skip_seek_lands_at_the_intro_end() {
    let Some(path) = sample() else { return };
    let chapters = ChapterPlan {
        intro_end_ms: Some(600),
        outro_start_ms: None,
    };
    let plan = plan_start(&short_clip_policy(), None, Some(1_000), &chapters);
    eprintln!("plan.start_ms={} reason={:?}", plan.start_ms, plan.reason);
    assert_eq!(plan.start_ms, 600, "片头结束点应直接作为起播点");

    let player = start();
    assert!(player.load(&path));
    wait_for(&player, Duration::from_secs(8), |s| s.time_pos.is_some())
        .expect("8 秒内没读到 time-pos");

    assert!(player.seek_absolute(plan.start_ms as f64 / 1000.0));
    let landed = wait_for(&player, Duration::from_secs(4), |s| {
        s.time_pos.is_some_and(|pos| pos >= 0.45)
    })
    .expect("跳片头后位置没有落在片头之后");
    eprintln!("跳片头落点: time-pos={:?}", landed.time_pos);
    player.quit();
}
