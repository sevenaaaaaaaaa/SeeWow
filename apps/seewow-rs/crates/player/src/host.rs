//! M1 的 mpv 宿主。
//!
//! **只有 player 线程调 libmpv**（这条是实现纪律，不是偏好）：
//!
//! - mpv 0.42 的 macOS 后端是 Swift，会用 `DispatchQueue.main.async` 做主线程上的
//!   VO/图层工作；主线程必须在事件循环里保持可被主队列调度；
//! - 主线程一旦去调 mpv（无论 `mpv_get_property` 还是 `loadfile`），就可能与
//!   mpv 自己的主线程工作互相等（实测：`mp_dispatch_lock` 上互锁，事件循环停摆）；
//! - 因此：命令走通道、属性在 player 线程读、主线程只用 `try_lock` 读快照，**永不等待**。
//!
//! 另：**不要设 `force-window=yes`**（见 Q-02）：无文件时先建窗会让 macOS VO 在
//! `swapBuffer` 上等，之后 `loadfile` 永不生效；窗口交给 mpv 在首帧自己创建。
//!
//! M3 的 T-09 会把这里的临时封装迁进 `mpv.rs` 并删掉（任务表 §0.3）。

use std::fmt::Write as _;
use std::fs::OpenOptions;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use libmpv2::Mpv;

use crate::probe::{TargetParams, f64_or_none, i64_or_none, str_or_none};

/// mpv 自己创建的宿主窗口标题 —— **定位窗口的键**（HLD §5.1 / §9.2）。
pub const HOST_WINDOW_TITLE: &str = "SeeWow Player";

/// M1 启动选项（HLD §5.1）。`cocoa-cb-output-csp` 先 `auto`，
/// 探测到源是 PQ/HLG 后才开成 `bt.2100-pq`（HLD §5.3 的实测项）。
pub const MPV_OPTIONS: &[(&str, &str)] = &[
    ("vo", "gpu-next"),
    ("gpu-api", "auto"),
    ("hwdec", "videotoolbox"),
    ("cocoa-cb-10bit-context", "yes"),
    ("cocoa-cb-output-csp", "auto"),
    ("cocoa-cb-sw-renderer", "no"),
    ("input-default-bindings", "no"),
    ("input-vo-keyboard", "no"),
    ("osc", "no"),
    ("osd-level", "0"),
    ("keep-open", "yes"),
    ("idle", "yes"),
    // 注意：**不设 force-window=yes**。实测（Q-02）：先在主线程建出 mpv 窗口再播放，
    // mpv 的 macOS VO 会卡在 swapBuffer，整个核心不再处理 loadfile；
    // 让 mpv 在真正有画面时自己建窗，播放就正常。
    ("border", "no"),
    ("title", HOST_WINDOW_TITLE),
    ("audio-exclusive", "no"),
];

/// 一次播放的状态快照（主线程按需生成）。
#[derive(Clone, Debug, Default)]
pub struct MpvSnapshot {
    pub pause: bool,
    pub time_pos: Option<f64>,
    pub duration: Option<f64>,
    /// 已经 loadfile 且 mpv 报得出时长/位置
    pub loaded: bool,
    pub eof_reached: bool,
    /// `options/cocoa-cb-output-csp` 的读回值（M1 用它代表图层色彩空间）
    pub csp: String,
    /// 源侧 `video-params/gamma`
    pub source_gamma: String,
    /// 目标侧 `video-target-params/*`（判定只用这一组）
    pub target: TargetParams,
    /// 面板「MPV」列的文本
    pub rows: String,
    /// target.* 不可用时的分项诊断（属性不存在 / 存在但为空）
    pub vo: crate::probe::VoDiagnostics,
}

/// `~/Library/Logs/SeeWow/m1.log`。M1 自带，不依赖 T-02 的日志门面。
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

/// libmpv 宿主：全进程只有一个实例（不变量 I2）。
///
/// 线程纪律（实测结论，见 Q-02）：
/// - **只有 player 线程调 libmpv**：mpv 的 Swift 后端用 `DispatchQueue.main.async` 做
///   VO 工作，主线程一旦自己调 mpv，就会和它互相等（`mp_dispatch_lock` 死锁）；
/// - 主线程**只用 `try_lock` 读快照**，永不等待 —— 主线程一阻塞，主队列就抽不干，
///   mpv 也就永远等不到它的主线程工作。
pub struct PlayerHost {
    log: Arc<M1Log>,
    commands: crossbeam_channel::Sender<HostCommand>,
    snapshot: Arc<Mutex<MpvSnapshot>>,
}

/// 主线程 → player 线程的命令。
#[derive(Clone, Debug)]
enum HostCommand {
    Load(PathBuf),
    SetPause(bool),
    SetOutputCsp(String),
    Quit,
}

impl PlayerHost {
    pub fn start(log: Arc<M1Log>) -> Result<Self, String> {
        log.write(
            "info",
            "mpv init: 开始初始化 libmpv（vo=gpu-next；窗口在首帧时由 mpv 自己创建）",
        );
        let mpv_log = log
            .path()
            .with_file_name("mpv.log")
            .to_string_lossy()
            .to_string();
        // 在主线程建 mpv（窗口创建/首帧要在主线程），之后把句柄整体交给 worker
        // 诊断开关：SEEWOW_MPV_VO=null 用来隔离「VO 卡住」与「命令卡住」
        let vo_override = std::env::var("SEEWOW_MPV_VO").ok();
        let mpv = Mpv::with_initializer(|init| {
            for (key, value) in MPV_OPTIONS {
                if vo_override.is_some()
                    && (*key == "vo" || *key == "force-window" || *key == "border")
                {
                    continue;
                }
                init.set_property(key, value.to_string())?;
            }
            if let Some(vo) = &vo_override {
                init.set_property("vo", vo.clone())?;
            }
            init.set_property("log-file", mpv_log)?;
            Ok(())
        })
        .map_err(|err| format!("libmpv 初始化失败：{err:?}"))?;

        let version = mpv
            .get_property::<String>("mpv-version")
            .ok()
            .unwrap_or_else(|| "n/a".to_string());
        log.write("info", &format!("mpv init: 完成 mpv-version={version}"));

        let (command_tx, command_rx) = crossbeam_channel::unbounded();
        let snapshot = Arc::new(Mutex::new(MpvSnapshot::default()));
        let thread_snapshot = snapshot.clone();
        let thread_log = log.clone();
        // 线程句柄不需要保存：进程退出即结束；quit 只发命令、不在主线程等
        std::thread::Builder::new()
            .name("seewow-player".to_string())
            .spawn(move || mpv_worker(mpv, command_rx, thread_snapshot, thread_log))
            .map_err(|err| format!("player 线程起不来：{err}"))?;

        Ok(Self {
            log,
            commands: command_tx,
            snapshot,
        })
    }

    pub fn log(&self) -> &Arc<M1Log> {
        &self.log
    }

    /// **非阻塞**读快照：拿不到锁就返回 `None`，调用方沿用上一次的值。
    pub fn try_snapshot(&self) -> Option<MpvSnapshot> {
        self.snapshot.try_lock().ok().map(|guard| guard.clone())
    }

    pub fn load(&self, path: &Path) {
        self.log.write(
            "info",
            &format!("playback: 请求 loadfile path={}", redact(path)),
        );
        let _ = self.commands.send(HostCommand::Load(path.to_path_buf()));
    }

    pub fn set_pause(&self, paused: bool) {
        let _ = self.commands.send(HostCommand::SetPause(paused));
    }

    /// 用快照状态取反（不阻塞）。
    pub fn toggle_pause(&self) -> bool {
        let next = !self.try_snapshot().map(|snap| snap.pause).unwrap_or(false);
        self.set_pause(next);
        next
    }

    pub fn set_output_csp(&self, csp: &str) {
        let _ = self
            .commands
            .send(HostCommand::SetOutputCsp(csp.to_string()));
    }

    /// 关闭：只发命令，**不在主线程 sleep 等**（退出路径要快；进程退出由 app 负责）。
    pub fn quit(&self) {
        self.log.write("info", "mpv: 请求 quit");
        let _ = self.commands.send(HostCommand::Quit);
    }
}

/// player 线程：命令 + 属性刷新。**只有这个线程碰 mpv。**
fn mpv_worker(
    mpv: Mpv,
    commands: crossbeam_channel::Receiver<HostCommand>,
    snapshot: Arc<Mutex<MpvSnapshot>>,
    log: Arc<M1Log>,
) {
    let mut playback: Option<(PathBuf, Instant)> = None;
    let mut last_refresh = Instant::now() - std::time::Duration::from_secs(1);

    loop {
        while let Ok(command) = commands.try_recv() {
            match command {
                HostCommand::Load(path) => {
                    let path_str = path.to_string_lossy().to_string();
                    match mpv.command("loadfile", &[&path_str]) {
                        Ok(()) => {
                            let mut line = String::new();
                            let _ = write!(
                                line,
                                "playback: begin format={} video={} {}x{} fps={} duration_ms={}",
                                prop_str(&mpv, "file-format"),
                                prop_str(&mpv, "video-format"),
                                prop_i64(&mpv, "width", -1),
                                prop_i64(&mpv, "height", -1),
                                prop_f64(&mpv, "container-fps")
                                    .map(|f| format!("{f:.3}"))
                                    .unwrap_or_else(|| "n/a".into()),
                                prop_f64(&mpv, "duration")
                                    .map(|d| (d * 1000.0) as i64)
                                    .unwrap_or(-1),
                            );
                            log.write("info", &line);
                            playback = Some((path, Instant::now()));
                        }
                        Err(err) => log.write("warn", &format!("playback: loadfile 失败 {err:?}")),
                    }
                }
                HostCommand::SetPause(paused) => match mpv.set_property("pause", paused) {
                    Ok(()) => log.write("info", &format!("playback: pause={paused}")),
                    Err(err) => log.write("warn", &format!("playback: set pause 失败 {err:?}")),
                },
                HostCommand::SetOutputCsp(csp) => {
                    match mpv
                        .set_property("options/cocoa-cb-output-csp", csp.clone())
                        .and_then(|_| mpv.set_property("cocoa-cb-output-csp", csp.clone()))
                    {
                        Ok(()) => log.write(
                            "info",
                            &format!(
                                "csp: 已请求 cocoa-cb-output-csp={csp}，之后 target.gamma={}",
                                prop_str(&mpv, "video-target-params/gamma")
                            ),
                        ),
                        Err(err) => log.write("warn", &format!("csp: 设置 {csp} 失败 {err:?}")),
                    }
                }
                HostCommand::Quit => {
                    log.write("info", "mpv: 收到 quit");
                    if let Some((path, started)) = playback.take() {
                        log_playback_end(&mpv, &log, &path, started, "quit");
                    }
                    if let Err(err) = mpv.command("quit", &[]) {
                        log.write("warn", &format!("mpv: quit 失败 {err:?}"));
                    }
                    std::mem::forget(mpv);
                    log.write("info", "mpv: player 线程退出");
                    return;
                }
            }
        }

        // 事件只用来做「活着」的判断（M1 不依赖事件驱动 UI）
        if let Some(Err(err)) = mpv.wait_event(0.02) {
            log.write("warn", &format!("mpv: wait_event 出错 {err:?}"));
        }

        if last_refresh.elapsed() >= std::time::Duration::from_millis(200) {
            last_refresh = Instant::now();
            refresh(&mpv, &snapshot);
        }
    }
}

/// 先把 mpv 的属性全部读出来（可能慢），再短暂持锁写入 —— 绝不持锁调 mpv。
fn refresh(mpv: &Mpv, snapshot: &Arc<Mutex<MpvSnapshot>>) {
    let target = TargetParams {
        gamma: prop_str(mpv, "video-target-params/gamma"),
        primaries: prop_str(mpv, "video-target-params/primaries"),
        max_luma: prop_f64(mpv, "video-target-params/max-luma"),
        min_luma: prop_f64(mpv, "video-target-params/min-luma"),
        pixelformat: prop_str(mpv, "video-target-params/pixelformat"),
    };
    let duration = prop_f64(mpv, "duration");
    let time_pos = prop_f64(mpv, "time-pos");
    let pause = mpv.get_property::<bool>("pause").unwrap_or(false);
    let eof_reached = mpv.get_property::<bool>("eof-reached").unwrap_or(false);
    let csp = prop_str(mpv, "options/cocoa-cb-output-csp");
    let source_gamma = prop_str(mpv, "video-params/gamma");
    let rows = build_rows(mpv);
    let vo = crate::probe::VoDiagnostics {
        current_vo: prop_str(mpv, "current-vo"),
        video_params: prop_state(mpv, "video-params"),
        target_params: prop_state(mpv, "video-target-params"),
    };

    if let Ok(mut slot) = snapshot.lock() {
        slot.pause = pause;
        slot.time_pos = time_pos;
        slot.duration = duration;
        slot.loaded = duration.is_some() || time_pos.is_some();
        slot.eof_reached = eof_reached;
        slot.csp = csp;
        slot.source_gamma = source_gamma;
        slot.target = target;
        slot.rows = rows;
        slot.vo = vo;
    }
}

/// 一个属性到底是「不存在」「存在但为空」还是「存在且非空」——诊断用，别混成 n/a。
fn prop_state(mpv: &Mpv, name: &str) -> String {
    match mpv.get_property::<String>(name) {
        Err(_) => "不存在".to_string(),
        Ok(value) if value.trim().is_empty() || value.trim() == "no" => "存在但为空".to_string(),
        Ok(_) => "存在且非空".to_string(),
    }
}

fn prop_str(mpv: &Mpv, name: &str) -> String {
    mpv.get_property::<String>(name)
        .ok()
        .and_then(|value| str_or_none(&value))
        .unwrap_or_else(|| "n/a".to_string())
}

fn prop_f64(mpv: &Mpv, name: &str) -> Option<f64> {
    mpv.get_property::<f64>(name).ok().and_then(f64_or_none)
}

fn prop_i64(mpv: &Mpv, name: &str, fallback: i64) -> i64 {
    mpv.get_property::<i64>(name)
        .ok()
        .and_then(i64_or_none)
        .unwrap_or(fallback)
}

fn log_playback_end(mpv: &Mpv, log: &M1Log, path: &Path, started: Instant, reason: &str) {
    log.write(
        "info",
        &format!(
            "playback: end reason={reason} path={} wall_ms={} frame-drop-count={} decoder-frame-drop-count={} mistimed-frame-count={}",
            redact(path),
            started.elapsed().as_millis(),
            prop_i64(mpv, "frame-drop-count", -1),
            prop_i64(mpv, "decoder-frame-drop-count", -1),
            prop_i64(mpv, "mistimed-frame-count", -1),
        ),
    );
}

fn build_rows(mpv: &Mpv) -> String {
    let mut lines: Vec<String> = Vec::new();
    let mut push = |label: &str, value: String| {
        if label.is_empty() {
            lines.push(String::new());
        } else if value.is_empty() {
            lines.push(label.to_string());
        } else {
            lines.push(format!("{label} {value}"));
        }
    };
    push("mpv", prop_str(mpv, "mpv-version"));
    push("vo", prop_str(mpv, "current-vo"));
    push("gpu-api", prop_str(mpv, "gpu-api"));
    push("hwdec", prop_str(mpv, "hwdec-current"));
    push("file", prop_str(mpv, "file-format"));
    push("video", prop_str(mpv, "video-format"));
    push("", String::new());
    push("video-params", String::new());
    push("gamma", prop_str(mpv, "video-params/gamma"));
    push("primaries", prop_str(mpv, "video-params/primaries"));
    push("pixfmt", prop_str(mpv, "video-params/pixelformat"));
    push(
        "max-luma",
        prop_f64(mpv, "video-params/max-luma")
            .map(|v| format!("{v:.1} cd/m²"))
            .unwrap_or_else(|| "n/a".into()),
    );
    push("", String::new());
    push("video-target-params", String::new());
    push("gamma", prop_str(mpv, "video-target-params/gamma"));
    push("primaries", prop_str(mpv, "video-target-params/primaries"));
    push("pixfmt", prop_str(mpv, "video-target-params/pixelformat"));
    push(
        "max-luma",
        prop_f64(mpv, "video-target-params/max-luma")
            .map(|v| format!("{v:.1} cd/m²"))
            .unwrap_or_else(|| "n/a".into()),
    );
    push(
        "min-luma",
        prop_f64(mpv, "video-target-params/min-luma")
            .map(|v| format!("{v:.4} cd/m²"))
            .unwrap_or_else(|| "n/a".into()),
    );
    push("", String::new());
    push(
        "size",
        format!(
            "{}x{} @ {}",
            prop_i64(mpv, "width", 0),
            prop_i64(mpv, "height", 0),
            prop_f64(mpv, "container-fps")
                .map(|f| format!("{f:.3}"))
                .unwrap_or_else(|| "n/a".into())
        ),
    );
    lines.join("\n")
}

/// 日志里不出现完整用户路径（不变量 I7 的 M1 版本：只留文件名）。
fn redact(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_else(|| "<unknown>".to_string())
}
