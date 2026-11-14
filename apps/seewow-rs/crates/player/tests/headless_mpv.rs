//! M3 起播探针：证明本机 libmpv 能在**无窗口**模式下真的解码播放。
//!
//! 默认跳过（CI 上没有 mpv / 没有视频文件），设置环境变量才跑：
//!   SEEWOW_MPV_TEST=1 SEEWOW_MPV_SAMPLE=/path/to/clip.mkv cargo test -p seewow-player --test headless_mpv -- --nocapture
//!
//! 这条测试的价值：在写 `mpv.rs` 之前，先确认「本机 libmpv + vo=null + loadfile +
//! time-pos 前进」这条最小链是通的，避免把环境问题误判成代码问题。

use std::time::{Duration, Instant};

use libmpv2::Mpv;

fn sample_path() -> Option<String> {
    std::env::var("SEEWOW_MPV_SAMPLE").ok()
}

#[test]
fn headless_playback_advances_time_pos() {
    if std::env::var("SEEWOW_MPV_TEST").as_deref() != Ok("1") {
        eprintln!("skip: 未设置 SEEWOW_MPV_TEST=1");
        return;
    }
    let path = sample_path().expect("SEEWOW_MPV_SAMPLE 指向一个视频文件");

    let start = Instant::now();
    let mpv = Mpv::with_initializer(|init| {
        init.set_option("vo", "null")?;
        init.set_option("ao", "null")?;
        init.set_option("audio-display", "no")?;
        init.set_option("terminal", "no")?;
        init.set_option("idle", "yes")?;
        Ok(())
    })
    .expect("创建 mpv 实例");

    let command_start = Instant::now();
    mpv.command("loadfile", &[&path, "replace"])
        .expect("loadfile");

    // 最多等 8 秒：time-pos 出现且 > 0.3 秒即算起播成功。
    let mut last = f64::NAN;
    let mut played = None;
    let mut polls = 0;
    while start.elapsed() < Duration::from_secs(8) {
        std::thread::sleep(Duration::from_millis(100));
        polls += 1;
        if let Ok(position) = mpv.get_property::<f64>("time-pos") {
            last = position;
            if position > 0.3 {
                played = Some(position);
                break;
            }
        }
    }

    let duration = mpv.get_property::<f64>("duration").unwrap_or(f64::NAN);
    let idle = mpv.get_property::<bool>("idle-active").unwrap_or(true);
    eprintln!(
        "mpv 起播: pos={last:.3}s duration={duration:.2}s idle_active={idle} \
         polls={polls} command_ms={} total_ms={}",
        command_start.elapsed().as_millis(),
        start.elapsed().as_millis()
    );
    assert!(played.is_some(), "8 秒内 time-pos 没有前进（last={last}）");
}
