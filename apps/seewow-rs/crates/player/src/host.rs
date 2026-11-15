//! M1 外壳胶水：日志门面 + 宿主窗口标题 + 播放器句柄。
//!
//! M3 T-09 把原本散在这个文件里的 libmpv 调用全部收编进 [`crate::mpv`]；这里只剩三件事：
//! 1. **日志门面** `M1Log`（`~/Library/Logs/SeeWow/m1.log`，每行 flush）；
//! 2. 把 `PlayerOptions` 组装好（vo 覆写、mpv 自己的日志文件、日志出口）；
//! 3. 对 app 暴露与 M1 相同的接口（`try_snapshot` / `load` / `set_pause` / `set_output_csp`
//!    / `quit` / `toggle_pause`），所以 app 侧不需要改调用点。
//!
//! 线程纪律没有变：**只有 player 线程碰 libmpv**，主线程只用 `try_lock` 读快照。

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use std::fs::OpenOptions;
use std::io::Write as _;

use crate::mpv::{LogSink, Player, PlayerOptions, PlayerSnapshot};

/// 兼容 M1 的旧名字：宿主窗口标题就是定位窗口的键。
pub use crate::mpv::{HOST_WINDOW_TITLE, MPV_OPTIONS, MpvSnapshot};

/// `~/Library/Logs/SeeWow/m1.log`。M1 自带，不依赖 core 的日志门面。
pub struct M1Log {
    path: PathBuf,
    file: Mutex<Option<std::fs::File>>,
}

impl M1Log {
    pub fn open() -> std::io::Result<Self> {
        let dir = log_dir();
        std::fs::create_dir_all(&dir)?;
        let path = dir.join("m1.log");
        let file = OpenOptions::new().create(true).append(true).open(&path)?;
        Ok(Self {
            path,
            file: Mutex::new(Some(file)),
        })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// 一行一条：`<UTC ISO8601> <level> <msg>`。每次 append 打开文件 ——
    /// 不持锁，就不会被 panic 毒化，任何线程都能写。
    pub fn write(&self, level: &str, msg: &str) {
        let line = format!("{} {level} {msg}\n", utc_stamp());
        // 句柄复用；写锁被毒化也照写（一次 panic 不该让日志从此哑掉）
        let Ok(mut slot) = self.file.lock().map_err(|poisoned| poisoned.into_inner()) else {
            return;
        };
        let file = slot.get_or_insert_with(|| {
            OpenOptions::new()
                .create(true)
                .append(true)
                .open(&self.path)
                .unwrap_or_else(|_| std::fs::File::create("/dev/null").expect("dev null"))
        });
        let _ = file.write_all(line.as_bytes());
        // 每行 flush：进程 exit / 崩溃时也要留住证据
        let _ = file.flush();
    }

    /// mpv 自己的日志文件：和 m1.log 同目录。
    pub fn mpv_log_path(&self) -> PathBuf {
        self.path.with_file_name("mpv.log")
    }
}

impl LogSink for M1Log {
    fn write(&self, level: &str, message: &str) {
        M1Log::write(self, level, message);
    }
}

fn log_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
        .join("Library")
        .join("Logs")
        .join("SeeWow")
}

fn utc_stamp() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default();
    let days = (secs / 86_400) as i64;
    let rem = (secs % 86_400) as u32;
    let (y, m, d) = civil_from_days(days);
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z",
        rem / 3600,
        (rem % 3600) / 60,
        rem % 60
    )
}

/// Howard Hinnant 的 days→civil 算法（不引日期库）。
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    if m <= 2 { (y + 1, m, d) } else { (y, m, d) }
}

/// 播放器句柄（M1 名字）。真正的 libmpv 操作在 [`crate::mpv::Player`]。
pub struct PlayerHost {
    log: Arc<M1Log>,
    player: Player,
}

impl PlayerHost {
    pub fn start(log: Arc<M1Log>) -> Result<Self, String> {
        log.write(
            "info",
            "mpv init: 开始初始化 libmpv（vo=gpu-next；窗口在首帧时由 mpv 自己创建）",
        );
        // 诊断开关：SEEWOW_MPV_VO=null 用来隔离「VO 卡住」与「命令卡住」。
        let vo_override = std::env::var("SEEWOW_MPV_VO").ok();
        let player = Player::start(PlayerOptions {
            vo_override,
            log_file: Some(log.mpv_log_path()),
            logger: Some(log.clone() as Arc<dyn LogSink>),
        })?;
        log.write(
            "info",
            &format!("mpv init: 完成 mpv-version={}", player.mpv_version()),
        );
        Ok(Self { log, player })
    }

    pub fn log(&self) -> &Arc<M1Log> {
        &self.log
    }

    /// 底层句柄：M3 起的播放控制（seek / 音量 / 倍速 / 字幕轨）都走这里。
    pub fn player(&self) -> &Player {
        &self.player
    }

    /// **非阻塞**读快照：拿不到锁就返回 `None`，调用方沿用上一次的值。
    pub fn try_snapshot(&self) -> Option<PlayerSnapshot> {
        self.player.try_snapshot()
    }

    pub fn load(&self, path: &Path) {
        self.player.load(path);
    }

    pub fn set_pause(&self, paused: bool) {
        self.player.set_pause(paused);
    }

    /// 用快照状态取反（不阻塞）。
    pub fn toggle_pause(&self) -> bool {
        self.player.toggle_pause()
    }

    pub fn set_output_csp(&self, csp: &str) {
        self.player.set_output_csp(csp);
    }

    /// 关闭：只发命令，**不在主线程 sleep 等**（退出路径要快；进程退出由 app 负责）。
    pub fn quit(&self) {
        self.log.write("info", "mpv: 请求 quit");
        self.player.quit();
    }
}
