//! T-09 验收：`Player` 在**无窗口**模式下真的能播、能停、能跳、能调音量/倍速。
//!
//! 默认跳过（CI 没有视频文件），设置环境变量才跑：
//!   SEEWOW_MPV_TEST=1 SEEWOW_MPV_SAMPLE=/path/clip.mkv \
//!     cargo test -p seewow-player --test player_api -- --nocapture --test-threads=1
//!
//! 每个断言对应 plan §3.6 中 T-09 DoD 的一条：起播、暂停后位置停住、seek ±300ms。

use std::path::PathBuf;
use std::time::{Duration, Instant};

use seewow_player::mpv::{Player, PlayerCommand, PlayerOptions};

fn sample() -> Option<PathBuf> {
    if std::env::var("SEEWOW_MPV_TEST").as_deref() != Ok("1") {
        eprintln!("skip: 未设置 SEEWOW_MPV_TEST=1");
        return None;
    }
    std::env::var("SEEWOW_MPV_SAMPLE").ok().map(PathBuf::from)
}

fn start() -> Player {
    Player::start(PlayerOptions {
        vo_override: Some("null".to_string()),
        log_file: None,
        logger: None,
    })
    .expect("创建 Player")
}

/// 轮询直到条件成立；返回最后一次快照。
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
        std::thread::sleep(Duration::from_millis(80));
    }
    None
}

#[test]
fn loads_and_advances_playback() {
    let Some(path) = sample() else { return };
    let player = start();
    assert!(player.load(&path));

    let started = Instant::now();
    let snapshot = wait_for(&player, Duration::from_secs(8), |s| {
        s.time_pos.is_some_and(|pos| pos > 0.2)
    })
    .expect("8 秒内 time-pos 没有前进");
    eprintln!(
        "起播: pos={:.3}s duration={:?} ms={}",
        snapshot.time_pos.unwrap_or_default(),
        snapshot.duration,
        started.elapsed().as_millis()
    );
    player.quit();
}

#[test]
fn pause_freezes_the_position() {
    let Some(path) = sample() else { return };
    let player = start();
    player.load(&path);
    wait_for(&player, Duration::from_secs(8), |s| {
        s.time_pos.is_some_and(|pos| pos > 0.2)
    })
    .expect("起播失败");

    player.set_pause(true);
    // 等 pause 真的生效。
    wait_for(&player, Duration::from_secs(3), |s| s.pause).expect("pause 没生效");
    let before = player
        .try_snapshot()
        .and_then(|s| s.time_pos)
        .unwrap_or_default();
    std::thread::sleep(Duration::from_millis(600));
    let after = player
        .try_snapshot()
        .and_then(|s| s.time_pos)
        .unwrap_or_default();
    eprintln!("暂停前后: {before:.3}s → {after:.3}s");
    assert!(
        (after - before).abs() < 0.15,
        "暂停后位置仍在走：{before} → {after}"
    );
    player.quit();
}

#[test]
fn absolute_seek_lands_within_300ms() {
    let Some(path) = sample() else { return };
    let player = start();
    player.load(&path);
    wait_for(&player, Duration::from_secs(8), |s| {
        s.time_pos.is_some_and(|pos| pos > 0.05)
    })
    .expect("起播失败");

    player.set_pause(true);
    wait_for(&player, Duration::from_secs(3), |s| s.pause).expect("pause 没生效");
    // 样片 1 秒：跳 0.8s 必须真的往前走。跳到 0.5 太容易「没动也算通过」。
    let before = player
        .try_snapshot()
        .and_then(|s| s.time_pos)
        .unwrap_or_default();
    assert!(player.seek_absolute(0.8));

    let snapshot = wait_for(&player, Duration::from_secs(4), |s| {
        s.time_pos.is_some_and(|pos| (pos - 0.8).abs() < 0.3)
    })
    .expect("seek 没有落在 0.8s ±300ms");
    let after = snapshot.time_pos.unwrap_or_default();
    eprintln!("seek 后: {before:.3}s → {after:.3}s");
    assert!(
        after > before + 0.3,
        "seek 后位置没有前进（{before:.3}s → {after:.3}s），命令可能被丢弃"
    );
    player.quit();
}

#[test]
fn volume_speed_and_track_commands_are_accepted() {
    let Some(path) = sample() else { return };
    let player = start();
    player.load(&path);
    wait_for(&player, Duration::from_secs(8), |s| {
        s.time_pos.is_some_and(|pos| pos > 0.05)
    })
    .expect("起播失败");

    assert!(player.set_volume(35.0));
    let volume = wait_for(&player, Duration::from_secs(3), |s| {
        (s.volume - 35.0).abs() < 1.0
    })
    .expect("音量没有生效");
    eprintln!("volume={}", volume.volume);

    assert!(player.set_speed(1.5));
    let speed = wait_for(&player, Duration::from_secs(3), |s| {
        (s.speed - 1.5).abs() < 0.05
    })
    .expect("倍速没有生效");
    eprintln!("speed={}", speed.speed);

    // 样片带音轨：track-list 应该至少给出一条。
    let tracks = player
        .try_snapshot()
        .map(|s| s.audio_tracks.len())
        .unwrap_or(0);
    eprintln!("audio_tracks={tracks}");
    assert!(tracks >= 1, "track-list 没读到音轨");

    // 字幕轨为空时 SelectSubtitle(None) 也必须被接受（不发命令到不存在的轨道）。
    assert!(player.select_subtitle(None));
    assert!(player.send(PlayerCommand::Stop));
    player.quit();
}

/// M1 的证据行（begin / end）在收编后必须还在：日志出口换成临时文件，跑一遍加载+退出。
#[test]
fn playback_evidence_lines_are_still_written() {
    let Some(path) = sample() else { return };
    let mut log_path = std::env::temp_dir();
    log_path.push(format!("seewow-player-evidence-{}.log", std::process::id()));
    std::fs::write(&log_path, "").unwrap();

    #[derive(Clone)]
    struct FileSink(std::sync::Arc<std::sync::Mutex<std::fs::File>>);
    impl seewow_player::mpv::LogSink for FileSink {
        fn write(&self, level: &str, message: &str) {
            use std::io::Write as _;
            if let Ok(mut file) = self.0.lock() {
                let _ = writeln!(file, "{level} {message}");
            }
        }
    }

    let file = std::fs::OpenOptions::new()
        .append(true)
        .open(&log_path)
        .unwrap();
    let sink = FileSink(std::sync::Arc::new(std::sync::Mutex::new(file)));

    let player = Player::start(PlayerOptions {
        vo_override: Some("null".to_string()),
        log_file: None,
        logger: Some(std::sync::Arc::new(sink)),
    })
    .expect("创建 Player");
    player.load(&path);
    wait_for(&player, Duration::from_secs(8), |s| {
        s.time_pos.is_some_and(|pos| pos > 0.1)
    })
    .expect("起播失败");
    player.quit();
    std::thread::sleep(Duration::from_millis(400));

    let logged = std::fs::read_to_string(&log_path).unwrap_or_default();
    eprintln!("证据行：\n{logged}");
    assert!(
        logged.contains("playback: 请求 loadfile"),
        "缺少 loadfile 请求行"
    );
    assert!(logged.contains("playback: begin"), "缺少 begin 证据行");
    assert!(
        logged.contains("playback: end"),
        "缺少 end 证据行（丢帧统计）"
    );
    assert!(
        !logged.contains("/tmp/seewow-realmedia"),
        "日志里不该出现完整用户路径"
    );
    let _ = std::fs::remove_file(&log_path);
}
