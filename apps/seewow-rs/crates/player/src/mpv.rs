//! libmpv 封装：进程里**唯一**的 mpv 实例、唯一的播放线程。
//!
//! 线程纪律（M1 实测结论，见规划 §2 与 Q-02）：
//!
//! - **只有 player 线程调 libmpv**。mpv 0.42 的 macOS 后端是 Swift，会用
//!   `DispatchQueue.main.async` 做 VO/图层工作；主线程若自己调 mpv，就会和它互相等
//!   （`mp_dispatch_lock` 死锁），事件循环停摆。
//! - 主线程**只用 `try_lock` 读快照**，永不等待：主线程一阻塞，主队列抽不干，mpv 也
//!   就永远等不到它的主线程工作。
//! - 命令一律走通道；参数由主线程算好，player 线程只负责执行。
//!
//! 为什么不设 `force-window=yes`：无文件时先建窗会让 macOS VO 卡在 `swapBuffer`，
//! 之后 `loadfile` 永不生效。窗口交给 mpv 在首帧自己创建。
//!
//! M3（T-09）把 M1 里散在 `host.rs` 的临时调用收编到这里；`host.rs` 只剩窗口/探针胶水。

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use libmpv2::Mpv;

use seewow_core::TrackInfo;

use crate::probe::{
    SourceParams, TargetParams, VoDiagnostics, f64_or_none, i64_or_none, str_or_none,
};

/// mpv 自己创建的宿主窗口标题 —— 定位窗口的键。
pub const HOST_WINDOW_TITLE: &str = "SeeWow Player";

/// M1 启动选项。`cocoa-cb-output-csp` 先 `auto`，探测到源是 PQ/HLG 后才开成
/// `bt.2100-pq`（M5 的实测项）。
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
    // 注意：**不设 force-window=yes**（Q-02）。
    ("border", "no"),
    ("title", HOST_WINDOW_TITLE),
    ("audio-exclusive", "no"),
];

/// 属性刷新间隔。200 ms 足够 UI 跟手，又不会把 player 线程刷满。
const REFRESH_INTERVAL: Duration = Duration::from_millis(200);

/// 一次播放的状态快照（player 线程写，主线程 `try_lock` 读）。
#[derive(Clone, Debug, Default)]
pub struct PlayerSnapshot {
    pub pause: bool,
    pub time_pos: Option<f64>,
    pub duration: Option<f64>,
    /// 已经 loadfile 且 mpv 报得出时长/位置。
    pub loaded: bool,
    pub eof_reached: bool,
    pub volume: f64,
    pub speed: f64,
    /// `options/cocoa-cb-output-csp` 的读回值（M1 用它代表图层色彩空间）。
    pub csp: String,
    /// 源侧 `video-params/gamma`。
    pub source_gamma: String,
    pub width: i64,
    pub height: i64,
    /// 音轨与字幕轨（来自 mpv `track-list`，不是猜文件名）。
    pub audio_tracks: Vec<TrackInfo>,
    pub subtitle_tracks: Vec<TrackInfo>,
    pub selected_subtitle: Option<i64>,
    /// 源侧 `video-params/*`（证据用：判定不看它，但日志要能复核「源是不是 PQ」）。
    pub source: SourceParams,
    /// 目标侧 `video-target-params/*`（判定只用这一组）。
    pub target: TargetParams,
    /// 面板「MPV」列的文本。
    pub rows: String,
    /// target.* 不可用时的分项诊断。
    pub vo: VoDiagnostics,
}

impl PlayerSnapshot {
    /// 当前位置（毫秒），方便与 `ResumePolicy` / `PlayerPreferences` 对接。
    pub fn position_ms(&self) -> i64 {
        self.time_pos
            .map(|value| (value * 1000.0) as i64)
            .unwrap_or(0)
    }

    pub fn duration_ms(&self) -> Option<i64> {
        self.duration.map(|value| (value * 1000.0) as i64)
    }
}

/// M1 叫 `MpvSnapshot`；保留别名让 app 侧平滑过渡。
pub type MpvSnapshot = PlayerSnapshot;

/// 主线程 → player 线程的命令。
#[derive(Clone, Debug, PartialEq)]
pub enum PlayerCommand {
    Load(PathBuf),
    SetPause(bool),
    /// 相对跳转（毫秒，可负）。
    SeekRelative {
        delta_ms: i64,
    },
    /// 绝对跳转（秒）。
    SeekAbsolute {
        seconds: f64,
    },
    SetVolume(f64),
    SetSpeed(f64),
    /// 选字幕轨；`None` 是关闭字幕。
    SelectSubtitle(Option<i64>),
    /// 挂一份外挂字幕。
    AddSubtitle(PathBuf),
    SetOutputCsp(String),
    Stop,
    Quit,
}

/// 日志出口。M1 的日志门面留在 `host.rs`，这里只依赖这个 trait，避免 mpv 层反过来依赖外壳。
pub trait LogSink: Send + Sync {
    fn write(&self, level: &str, message: &str);
}

/// 启动参数。
#[derive(Clone, Default)]
pub struct PlayerOptions {
    /// 诊断用：把 `vo` 覆写成 `null`（无窗口起播）。
    pub vo_override: Option<String>,
    /// mpv 自己的日志文件。
    pub log_file: Option<PathBuf>,
    /// 日志出口；`None` 表示不记日志（测试用）。
    pub logger: Option<Arc<dyn LogSink>>,
}

impl std::fmt::Debug for PlayerOptions {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PlayerOptions")
            .field("vo_override", &self.vo_override)
            .field("log_file", &self.log_file)
            .field("logger", &self.logger.is_some())
            .finish()
    }
}

/// 播放器句柄。`Drop` 不发命令：退出路径由调用方显式 `quit()`，避免析构时阻塞主线程。
pub struct Player {
    commands: crossbeam_channel::Sender<PlayerCommand>,
    snapshot: Arc<Mutex<PlayerSnapshot>>,
    version: String,
}

impl std::fmt::Debug for Player {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Player")
            .field("mpv_version", &self.version)
            .finish_non_exhaustive()
    }
}

impl Player {
    /// 创建 mpv 并起 player 线程。
    ///
    /// 注意：mpv 在这里（调用线程）创建——窗口/首帧相关工作要主线程；创建完立刻把句柄
    /// 交给 worker，之后调用线程不再碰它。
    pub fn start(options: PlayerOptions) -> Result<Self, String> {
        let vo_override = options.vo_override.clone();
        let log_file = options.log_file.clone();
        let mpv = Mpv::with_initializer(|init| {
            for (key, value) in MPV_OPTIONS {
                if vo_override.is_some() && matches!(*key, "vo" | "force-window" | "border") {
                    continue;
                }
                init.set_property(key, value.to_string())?;
            }
            if let Some(vo) = &vo_override {
                init.set_property("vo", vo.clone())?;
                // 无窗口模式没什么可画的，关掉音频输出也省得占设备。
                init.set_property("ao", "null")?;
            }
            if let Some(path) = &log_file {
                init.set_property("log-file", path.to_string_lossy().to_string())?;
            }
            Ok(())
        })
        .map_err(|err| format!("libmpv 初始化失败：{err:?}"))?;

        let version = mpv
            .get_property::<String>("mpv-version")
            .ok()
            .unwrap_or_else(|| "n/a".to_string());

        let logger = options.logger.clone();
        let (commands, command_rx) = crossbeam_channel::unbounded();
        let snapshot = Arc::new(Mutex::new(PlayerSnapshot {
            volume: 100.0,
            speed: 1.0,
            ..PlayerSnapshot::default()
        }));
        let thread_snapshot = snapshot.clone();
        std::thread::Builder::new()
            .name("seewow-player".to_string())
            .spawn(move || worker(mpv, command_rx, thread_snapshot, logger))
            .map_err(|err| format!("player 线程起不来：{err}"))?;

        Ok(Self {
            commands,
            snapshot,
            version,
        })
    }

    pub fn mpv_version(&self) -> &str {
        &self.version
    }

    /// **非阻塞**读快照：拿不到锁就返回 `None`，调用方沿用上一次的值。
    pub fn try_snapshot(&self) -> Option<PlayerSnapshot> {
        self.snapshot.try_lock().ok().map(|guard| guard.clone())
    }

    /// 发命令；通道断了（线程已退出）返回 `false`，不 panic。
    pub fn send(&self, command: PlayerCommand) -> bool {
        self.commands.send(command).is_ok()
    }

    pub fn load(&self, path: &Path) -> bool {
        self.send(PlayerCommand::Load(path.to_path_buf()))
    }

    pub fn set_pause(&self, paused: bool) -> bool {
        self.send(PlayerCommand::SetPause(paused))
    }

    /// 用快照状态取反（不阻塞）。
    pub fn toggle_pause(&self) -> bool {
        let next = !self.try_snapshot().map(|snap| snap.pause).unwrap_or(false);
        self.set_pause(next);
        next
    }

    pub fn seek_relative_ms(&self, delta_ms: i64) -> bool {
        self.send(PlayerCommand::SeekRelative { delta_ms })
    }

    pub fn seek_absolute(&self, seconds: f64) -> bool {
        self.send(PlayerCommand::SeekAbsolute { seconds })
    }

    pub fn set_volume(&self, volume: f64) -> bool {
        self.send(PlayerCommand::SetVolume(volume))
    }

    pub fn set_speed(&self, speed: f64) -> bool {
        self.send(PlayerCommand::SetSpeed(speed))
    }

    pub fn select_subtitle(&self, id: Option<i64>) -> bool {
        self.send(PlayerCommand::SelectSubtitle(id))
    }

    pub fn add_subtitle(&self, path: &Path) -> bool {
        self.send(PlayerCommand::AddSubtitle(path.to_path_buf()))
    }

    pub fn set_output_csp(&self, csp: &str) -> bool {
        self.send(PlayerCommand::SetOutputCsp(csp.to_string()))
    }

    /// 停止播放但保留实例（回到 idle）。
    pub fn stop(&self) -> bool {
        self.send(PlayerCommand::Stop)
    }

    /// 关闭：只发命令，**不在调用线程 sleep 等**。
    pub fn quit(&self) -> bool {
        self.send(PlayerCommand::Quit)
    }
}

/// player 线程：命令 + 属性刷新。**只有这个线程碰 mpv。**
fn worker(
    mpv: Mpv,
    commands: crossbeam_channel::Receiver<PlayerCommand>,
    snapshot: Arc<Mutex<PlayerSnapshot>>,
    logger: Option<Arc<dyn LogSink>>,
) {
    let mut last_refresh = Instant::now() - REFRESH_INTERVAL;
    // M1 的证据行：begin（文件真的加载了）与 end（退出时的丢帧数）必须照旧写出来。
    let mut playback: Option<(PathBuf, Instant)> = None;
    let mut pending_begin: Option<(PathBuf, Instant)> = None;
    loop {
        while let Ok(command) = commands.try_recv() {
            match command {
                PlayerCommand::Load(path) => {
                    log(
                        &logger,
                        "info",
                        &format!("playback: 请求 loadfile path={}", redact(&path)),
                    );
                    let path_str = path.to_string_lossy().to_string();
                    match mpv.command("loadfile", &[&path_str, "replace"]) {
                        Ok(()) => {
                            pending_begin = Some((path.clone(), Instant::now()));
                            playback = Some((path, Instant::now()));
                        }
                        Err(err) => {
                            log(&logger, "warn", &format!("playback: loadfile 失败 {err:?}"));
                        }
                    }
                }
                PlayerCommand::SetPause(paused) => match mpv.set_property("pause", paused) {
                    Ok(()) => log(&logger, "info", &format!("playback: pause={paused}")),
                    Err(err) => {
                        log(
                            &logger,
                            "warn",
                            &format!("playback: set pause 失败 {err:?}"),
                        );
                    }
                },
                PlayerCommand::SeekRelative { delta_ms } => {
                    let seconds = delta_ms as f64 / 1000.0;
                    let _ = mpv.command("seek", &[&format!("{seconds:.3}"), "relative"]);
                }
                PlayerCommand::SeekAbsolute { seconds } => {
                    let _ = mpv.command("seek", &[&format!("{seconds:.3}"), "absolute"]);
                }
                PlayerCommand::SetVolume(volume) => {
                    let _ = mpv.set_property("volume", volume.clamp(0.0, 100.0));
                }
                PlayerCommand::SetSpeed(speed) => {
                    let _ = mpv.set_property("speed", speed.clamp(0.25, 8.0));
                }
                PlayerCommand::SelectSubtitle(id) => match id {
                    Some(id) => {
                        let _ = mpv.set_property("sid", id);
                    }
                    None => {
                        let _ = mpv.set_property("sid", "no");
                    }
                },
                PlayerCommand::AddSubtitle(path) => {
                    let path_str = path.to_string_lossy().to_string();
                    let _ = mpv.command("sub-add", &[&path_str]);
                }
                PlayerCommand::SetOutputCsp(csp) => {
                    let result = mpv
                        .set_property("options/cocoa-cb-output-csp", csp.clone())
                        .and_then(|()| mpv.set_property("cocoa-cb-output-csp", csp.clone()));
                    match result {
                        Ok(()) => log(
                            &logger,
                            "info",
                            &format!(
                                "csp: 已请求 cocoa-cb-output-csp={csp}，之后 target.gamma={}",
                                prop_str(&mpv, "video-target-params/gamma")
                            ),
                        ),
                        Err(err) => {
                            log(&logger, "warn", &format!("csp: 设置 {csp} 失败 {err:?}"));
                        }
                    }
                }
                PlayerCommand::Stop => {
                    let _ = mpv.command("stop", &[]);
                }
                PlayerCommand::Quit => {
                    log(&logger, "info", "mpv: 收到 quit");
                    if let Some((path, started)) = playback.take() {
                        log_playback_end(&mpv, &logger, &path, started, "quit");
                    }
                    if let Err(err) = mpv.command("quit", &[]) {
                        log(&logger, "warn", &format!("mpv: quit 失败 {err:?}"));
                    }
                    // 不在 player 线程销毁 mpv（窗口销毁要主线程）；进程即将退出。
                    std::mem::forget(mpv);
                    log(&logger, "info", "mpv: player 线程退出");
                    return;
                }
            }
        }

        let _ = mpv.wait_event(0.02);

        // 等「文件已加载」且「源侧参数就绪」再打 begin，避免 format=n/a；最多等 1.5 秒。
        if let Some((path, since)) = pending_begin.clone() {
            let file_format = prop_str(&mpv, "file-format");
            let source_gamma = prop_str(&mpv, "video-params/gamma");
            let ready = file_format != "n/a" && source_gamma != "n/a";
            if ready || since.elapsed() >= Duration::from_millis(1500) {
                log(
                    &logger,
                    "info",
                    &format!(
                        "playback: begin file={} format={} video={} {}x{} fps={} duration_ms={} source.gamma={} source.primaries={} source.pixfmt={}",
                        redact(&path),
                        file_format,
                        prop_str(&mpv, "video-format"),
                        prop_i64(&mpv, "width", -1),
                        prop_i64(&mpv, "height", -1),
                        prop_f64(&mpv, "container-fps")
                            .map(|f| format!("{f:.3}"))
                            .unwrap_or_else(|| "n/a".into()),
                        prop_f64(&mpv, "duration")
                            .map(|d| (d * 1000.0) as i64)
                            .unwrap_or(-1),
                        prop_str(&mpv, "video-params/gamma"),
                        prop_str(&mpv, "video-params/primaries"),
                        prop_str(&mpv, "video-params/pixelformat"),
                    ),
                );
                pending_begin = None;
            }
        }

        if last_refresh.elapsed() >= REFRESH_INTERVAL {
            last_refresh = Instant::now();
            refresh(&mpv, &snapshot);
        }
    }
}

/// 先读属性（可能慢），再短暂持锁写入 —— 绝不持锁调 mpv。
fn refresh(mpv: &Mpv, snapshot: &Arc<Mutex<PlayerSnapshot>>) {
    let target = TargetParams {
        gamma: prop_str(mpv, "video-target-params/gamma"),
        primaries: prop_str(mpv, "video-target-params/primaries"),
        max_luma: prop_f64(mpv, "video-target-params/max-luma"),
        min_luma: prop_f64(mpv, "video-target-params/min-luma"),
        pixelformat: prop_str(mpv, "video-target-params/pixelformat"),
    };
    let source = SourceParams {
        gamma: prop_str(mpv, "video-params/gamma"),
        primaries: prop_str(mpv, "video-params/primaries"),
        pixelformat: prop_str(mpv, "video-params/pixelformat"),
        width: prop_i64(mpv, "video-params/w", prop_i64(mpv, "width", 0)),
        height: prop_i64(mpv, "video-params/h", prop_i64(mpv, "height", 0)),
    };
    let duration = prop_f64(mpv, "duration");
    let time_pos = prop_f64(mpv, "time-pos");
    let pause = mpv.get_property::<bool>("pause").unwrap_or(false);
    let eof_reached = mpv.get_property::<bool>("eof-reached").unwrap_or(false);
    let volume = prop_f64(mpv, "volume").unwrap_or(100.0);
    let speed = prop_f64(mpv, "speed").unwrap_or(1.0);
    let csp = prop_str(mpv, "options/cocoa-cb-output-csp");
    let source_gamma = prop_str(mpv, "video-params/gamma");
    let width = prop_i64(mpv, "width", 0);
    let height = prop_i64(mpv, "height", 0);
    let audio_tracks = track_list(mpv, "audio");
    let subtitle_tracks = track_list(mpv, "sub");
    let selected_subtitle = mpv.get_property::<i64>("sid").ok();
    let rows = build_rows(mpv);
    let vo = VoDiagnostics {
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
        slot.volume = volume;
        slot.speed = speed;
        slot.csp = csp;
        slot.source_gamma = source_gamma;
        slot.width = width;
        slot.height = height;
        slot.audio_tracks = audio_tracks;
        slot.subtitle_tracks = subtitle_tracks;
        slot.selected_subtitle = selected_subtitle;
        slot.source = source;
        slot.target = target;
        slot.rows = rows;
        slot.vo = vo;
    }
}

fn log(logger: &Option<Arc<dyn LogSink>>, level: &str, message: &str) {
    if let Some(logger) = logger {
        logger.write(level, message);
    }
}

fn log_playback_end(
    mpv: &Mpv,
    logger: &Option<Arc<dyn LogSink>>,
    path: &Path,
    started: Instant,
    reason: &str,
) {
    log(
        logger,
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

/// 日志里不出现完整用户路径：只留文件名。
pub fn redact(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_else(|| "<unknown>".to_string())
}

/// 读 mpv 的轨道列表。用 `track-list/count` + 逐项属性，避免依赖 node 反序列化。
fn track_list(mpv: &Mpv, kind: &str) -> Vec<TrackInfo> {
    let count = prop_i64(mpv, "track-list/count", 0).clamp(0, 64);
    let mut tracks = Vec::new();
    for index in 0..count {
        let track_type = prop_str(mpv, &format!("track-list/{index}/type"));
        if track_type != kind {
            continue;
        }
        let id = prop_i64(mpv, &format!("track-list/{index}/id"), -1);
        if id < 0 {
            continue;
        }
        let language = prop_opt_str(mpv, &format!("track-list/{index}/lang"));
        let title = prop_opt_str(mpv, &format!("track-list/{index}/title"));
        tracks.push(TrackInfo {
            id,
            language,
            title,
        });
    }
    tracks
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
    prop_opt_str(mpv, name).unwrap_or_else(|| "n/a".to_string())
}

fn prop_opt_str(mpv: &Mpv, name: &str) -> Option<String> {
    mpv.get_property::<String>(name)
        .ok()
        .and_then(|value| str_or_none(&value))
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

fn build_rows(mpv: &Mpv) -> String {
    let mut lines: Vec<String> = Vec::new();
    let push = |lines: &mut Vec<String>, label: &str, value: String| {
        if label.is_empty() {
            lines.push(String::new());
        } else if value.is_empty() {
            lines.push(label.to_string());
        } else {
            lines.push(format!("{label} {value}"));
        }
    };
    push(&mut lines, "mpv", prop_str(mpv, "mpv-version"));
    push(&mut lines, "vo", prop_str(mpv, "current-vo"));
    push(&mut lines, "gpu-api", prop_str(mpv, "gpu-api"));
    push(&mut lines, "hwdec", prop_str(mpv, "hwdec-current"));
    push(&mut lines, "file", prop_str(mpv, "file-format"));
    push(&mut lines, "video", prop_str(mpv, "video-format"));
    push(&mut lines, "", String::new());
    push(&mut lines, "video-params", String::new());
    push(&mut lines, "gamma", prop_str(mpv, "video-params/gamma"));
    push(
        &mut lines,
        "primaries",
        prop_str(mpv, "video-params/primaries"),
    );
    push(
        &mut lines,
        "pixfmt",
        prop_str(mpv, "video-params/pixelformat"),
    );
    push(
        &mut lines,
        "max-luma",
        prop_f64(mpv, "video-params/max-luma")
            .map(|v| format!("{v:.1} cd/m²"))
            .unwrap_or_else(|| "n/a".into()),
    );
    push(&mut lines, "", String::new());
    push(&mut lines, "video-target-params", String::new());
    push(
        &mut lines,
        "gamma",
        prop_str(mpv, "video-target-params/gamma"),
    );
    push(
        &mut lines,
        "primaries",
        prop_str(mpv, "video-target-params/primaries"),
    );
    push(
        &mut lines,
        "pixfmt",
        prop_str(mpv, "video-target-params/pixelformat"),
    );
    push(
        &mut lines,
        "max-luma",
        prop_f64(mpv, "video-target-params/max-luma")
            .map(|v| format!("{v:.1} cd/m²"))
            .unwrap_or_else(|| "n/a".into()),
    );
    push(
        &mut lines,
        "min-luma",
        prop_f64(mpv, "video-target-params/min-luma")
            .map(|v| format!("{v:.4} cd/m²"))
            .unwrap_or_else(|| "n/a".into()),
    );
    push(&mut lines, "", String::new());
    push(
        &mut lines,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_converts_seconds_to_milliseconds() {
        let snapshot = PlayerSnapshot {
            time_pos: Some(12.345),
            duration: Some(90.0),
            ..PlayerSnapshot::default()
        };
        assert_eq!(snapshot.position_ms(), 12_345);
        assert_eq!(snapshot.duration_ms(), Some(90_000));
    }

    #[test]
    fn empty_snapshot_has_sane_defaults() {
        let snapshot = PlayerSnapshot::default();
        assert_eq!(snapshot.position_ms(), 0);
        assert_eq!(snapshot.duration_ms(), None);
        assert!(!snapshot.loaded);
        assert!(snapshot.audio_tracks.is_empty());
    }

    #[test]
    fn commands_are_comparable_for_tests() {
        // 命令是纯数据，测试与日志都能直接比对。
        assert_eq!(
            PlayerCommand::SeekRelative { delta_ms: -10_000 },
            PlayerCommand::SeekRelative { delta_ms: -10_000 }
        );
        assert_ne!(
            PlayerCommand::SelectSubtitle(Some(1)),
            PlayerCommand::SelectSubtitle(None)
        );
    }
}
