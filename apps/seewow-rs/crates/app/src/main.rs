//! SeeWow 入口（M1 走通骨架的 composition root）。
//!
//! 顺序按 HLD §9.2：
//! 1. Slint 组件先建、**不 show**（避免改窗口属性时闪白）；
//! 2. 拉起 mpv（窗口由 mpv 在首帧自己创建；**不设 force-window**），把 `Mpv` 交给 player 线程；
//! 3. 0.1s 的 tick 在 `NSApp.windows` 里按 **类名 `swift.Window`** 定位宿主窗口（标题会被 mpv 改成媒体名）；
//! 4. show 叠层 → 透明加固 → 挂成宿主窗口的子窗口 → 装 `NSEvent` 监视器；
//! 5. 播放 / 探针 / 全屏 / 换屏全部由 tick 维护；**主线程从不直接调 libmpv**。
//!
//! 验证用：`seewow-app <file>` 直接播这个文件；
//! `SEEWOW_SELFTEST=1 seewow-app <file>` 走「全屏进 → 全屏出 → 退出」的脚本化自检。

use std::path::PathBuf;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use slint::ComponentHandle as _;

use seewow_app::playback::{self, PlaybackPage};
use seewow_core::{Paths, PlayerPreferences, ResumePolicy};
use seewow_library::Library;
use seewow_player::host::{HOST_WINDOW_TITLE, M1Log, PlayerHost};
use seewow_player::mpv::PlayerSnapshot;
use seewow_player::probe::{ProbeSeed, Verdict, judge};
use seewow_player::window as host_window;
use seewow_ui::hit::{self, Flags, InputSink};
use seewow_ui::overlay::{self, OVERLAY_WINDOW_TITLE};
use seewow_ui::skeleton::{Shell, Skeleton, clock_label};

mod cli;

/// 定位宿主窗口的最多尝试次数（0.1s 一次 → 约 2s，HLD §9.2 step 3）。
const LOCATE_TRIES: u32 = 20;

struct OverlayHandle {
    overlay: objc2::rc::Retained<objc2_app_kit::NSWindow>,
    host: objc2::rc::Retained<objc2_app_kit::NSWindow>,
}

impl Clone for OverlayHandle {
    fn clone(&self) -> Self {
        Self {
            overlay: self.overlay.clone(),
            host: self.host.clone(),
        }
    }
}

struct Core {
    log: Arc<M1Log>,
    host: Arc<PlayerHost>,
    ui: slint::Weak<Skeleton>,
    shared: Arc<hit::Shared>,
    overlay: Mutex<Option<OverlayHandle>>,
    monitor: Mutex<Option<hit::InputMonitor>>,
    autoplay: Option<PathBuf>,
    /// 片库：续播进度与片头片尾都靠它；打不开就降级成「能播，但没有续播」。
    library: Mutex<Option<Library>>,
    /// 起播/落盘的判定口径（T-10 的 ResumePolicy，这里不另立阈值）。
    policy: ResumePolicy,
    /// 默认音轨/字幕语言、连播、步长（T-13）。
    prefs: PlayerPreferences,
    /// 当前这一页的播放会话：认条目、片头片尾、落盘水位。
    page: Mutex<Option<PlaybackPage>>,
    /// 起播决定要 seek 的位置：等 mpv 报出 time-pos 再跳，否则 seek 会丢。
    pending_seek_ms: Mutex<Option<i64>>,
    /// 字幕菜单只在 track-list 或选中轨变化时重建（每 0.1s 重建会白拉 Slint 模型）。
    last_subtitle_state: Mutex<Option<(usize, Option<i64>)>>,
    locate_tries: AtomicU32,
    load_requested: AtomicBool,
    shown: AtomicBool,
    standalone: AtomicBool,
    playing: AtomicBool,
    saw_loaded: AtomicBool,
    hdr_csp_sent: AtomicBool,
    shutdown_done: AtomicBool,
    last_probe_at: Mutex<Instant>,
    last_probe_log_at: Mutex<Instant>,
    last_screen: Mutex<String>,
    last_snapshot: Mutex<seewow_player::host::MpvSnapshot>,
    /// 长按加速前的倍速；松手要原样恢复。
    base_speed: Mutex<f64>,
    last_screen_state: Mutex<seewow_player::probe::ScreenState>,
    last_logged_frame: Mutex<Option<(f64, f64, f64, f64)>>,
    last_probe_key: Mutex<String>,
    last_scan_diag_at: Mutex<Instant>,
    last_target_diag_at: Mutex<Instant>,
    selftest: bool,
    selftest_step: AtomicU32,
    ticks: AtomicU32,
    started: Instant,
}

impl Core {
    /// 上次从 player 线程拿到的快照（**永不阻塞主线程**）。
    fn snapshot(&self) -> seewow_player::host::MpvSnapshot {
        if let Some(fresh) = self.host.try_snapshot()
            && let Ok(mut cache) = self.last_snapshot.lock()
        {
            *cache = fresh;
        }
        self.last_snapshot
            .lock()
            .map(|cache| cache.clone())
            .unwrap_or_default()
    }

    /// 读叠层句柄（**毒化也照读**：一次 panic 不该把整条路径永久废掉）
    fn overlay_handle(&self) -> Option<OverlayHandle> {
        match self.overlay.lock() {
            Ok(guard) => guard.clone(),
            Err(poisoned) => {
                self.log
                    .write("warn", "overlay: 句柄锁被毒化，按未中毒继续读");
                poisoned.into_inner().clone()
            }
        }
    }

    fn store_overlay(&self, handle: OverlayHandle) {
        match self.overlay.lock() {
            Ok(mut slot) => *slot = Some(handle),
            Err(poisoned) => *poisoned.into_inner() = Some(handle),
        }
        self.log
            .write("info", "overlay: 句柄已保存（本 tick 起不再重复挂载）");
    }

    fn layout_from_slint(&self) -> hit::Layout {
        let Some(ui) = self.ui.upgrade() else {
            return hit::Layout::default();
        };
        // 尺寸以真实 NSWindow 的 frame 为准（两者都是无边框窗口，frame 即内容区）
        let frame_size = self
            .overlay
            .lock()
            .ok()
            .and_then(|guard| guard.as_ref().map(|handle| overlay::frame(&handle.overlay)))
            .map(|(_, _, width, height)| (width as f32, height as f32));
        let fallback = ui.window().size();
        let (width, height) = frame_size.unwrap_or((fallback.width as f32, fallback.height as f32));
        hit::Layout {
            width,
            height,
            header_h: ui.get_header_h(),
            gutter: ui.get_gutter(),
            controls_h: ui.get_controls_h(),
            traffic_w: ui.get_traffic_w(),
            traffic_h: ui.get_traffic_h(),
            probe_w: ui.get_probe_w(),
            probe_h: ui.get_probe_h(),
            top_edge: ui.get_top_edge(),
            header_actions_w: ui.get_header_actions_w(),
        }
    }

    /// 片库读锁：毒化也照读（一次 panic 不该让续播永久失效）。
    fn with_library<T>(&self, action: impl FnOnce(Option<&Library>) -> T) -> T {
        match self.library.lock() {
            Ok(guard) => action(guard.as_ref()),
            Err(poisoned) => {
                self.log.write("warn", "library: 锁被毒化，按未中毒继续读");
                action(poisoned.into_inner().as_ref())
            }
        }
    }

    /// 打开一个文件（自动播放与「打开文件」都走这里）：
    /// 认条目 → 读片头片尾与上次进度 → 得到起播点 → 交给 mpv。
    fn open_media(self: &Rc<Self>, path: PathBuf) {
        // 换片前先给上一部落盘，否则「关掉再打开」会丢最后一次位置。
        self.flush_current_progress();
        let page = self.with_library(|library| PlaybackPage::open(library, &path));
        let plan = page.plan(&self.policy, None);
        self.log.write(
            "info",
            &format!(
                "playback: 打开 {} → 起播 {}ms reason={} show={:?} intro={:?} outro={:?}",
                path.display(),
                plan.start_ms,
                plan.reason.as_str(),
                page.session.key.show_key,
                page.session.chapters.intro_end_ms,
                page.session.chapters.outro_start_ms,
            ),
        );
        // 换片：把「上一部已加载」的判定清掉，否则这一部不会走「首帧后 seek」那条路。
        self.saw_loaded.store(false, Ordering::SeqCst);
        self.hdr_csp_sent.store(false, Ordering::SeqCst);
        self.playing.store(false, Ordering::SeqCst);
        if let Ok(mut slot) = self.pending_seek_ms.lock() {
            *slot = (plan.start_ms > 0).then_some(plan.start_ms);
        }
        if let Ok(mut slot) = self.last_subtitle_state.lock() {
            *slot = None;
        }
        if let Ok(mut slot) = self.page.lock() {
            *slot = Some(page);
        }
        if let Some(ui) = self.ui.upgrade() {
            ui.set_outro_visible(false);
            ui.set_subtitle_menu_open(false);
            ui.set_subtitle_label("CC".into());
            ui.set_media_title(file_stem(&path).into());
        }
        self.host.load(&path);
    }

    /// 起播决定落到实处：mpv 报出 time_pos 之后再 seek 才不会丢。
    fn apply_start_plan(&self) {
        let pending = match self.pending_seek_ms.lock() {
            Ok(mut slot) => slot.take(),
            Err(poisoned) => poisoned.into_inner().take(),
        };
        let Some(start_ms) = pending else { return };
        let seconds = start_ms as f64 / 1000.0;
        if self.host.player().seek_absolute(seconds) {
            self.log.write(
                "info",
                &format!("playback: 起播 seek → {seconds:.3}s（{start_ms}ms）"),
            );
        } else {
            self.log.write(
                "warn",
                &format!("playback: 起播 seek 失败（{start_ms}ms），从头播"),
            );
        }
    }

    /// 默认字幕：按 T-13 的偏好从 track-list 里挑；挑不到就说「没有」，不偷偷选第一条。
    fn apply_default_subtitle(&self, snapshot: &PlayerSnapshot) {
        if snapshot.subtitle_tracks.is_empty() {
            self.log
                .write("info", "playback: 这条片源没有字幕轨（track-list 为空）");
            return;
        }
        match self.prefs.pick_subtitle(&snapshot.subtitle_tracks) {
            Some(track) => {
                let id = track.id;
                let label = track
                    .title
                    .clone()
                    .or_else(|| track.language.clone())
                    .unwrap_or_default();
                if self.host.player().select_subtitle(Some(id)) {
                    self.log
                        .write("info", &format!("playback: 默认字幕 track={id}（{label}）"));
                }
            }
            None => self.log.write(
                "warn",
                &format!(
                    "playback: 没有匹配 {:?} 的字幕轨（共 {} 条），保持片源默认",
                    self.prefs.default_subtitle_language,
                    snapshot.subtitle_tracks.len()
                ),
            ),
        }
    }

    /// 字幕菜单：条目、选中、控制条上的短标签，全部来自 mpv track-list。
    fn refresh_subtitle_menu(&self, snapshot: &PlayerSnapshot) {
        let key = (snapshot.subtitle_tracks.len(), snapshot.selected_subtitle);
        let changed = self
            .last_subtitle_state
            .lock()
            .map(|last| *last != Some(key))
            .unwrap_or(true);
        if !changed {
            return;
        }
        if let Ok(mut last) = self.last_subtitle_state.lock() {
            *last = Some(key);
        }
        let menu = playback::subtitle_menu(&snapshot.subtitle_tracks, snapshot.selected_subtitle);
        if let Some(ui) = self.ui.upgrade() {
            ui.set_subtitles_on(menu.selected.is_some());
            ui.set_subtitle_label(menu.summary.clone().into());
            let labels: Vec<slint::SharedString> = menu
                .items
                .iter()
                .map(|item| slint::SharedString::from(item.label.as_str()))
                .collect();
            ui.set_subtitle_items(slint::ModelRc::new(slint::VecModel::from(labels)));
        }
        self.log.write(
            "info",
            &format!(
                "playback: 字幕轨 {} 条 [{}] selected={:?}",
                menu.items.len(),
                menu.items
                    .iter()
                    .map(|item| item.label.as_str())
                    .collect::<Vec<_>>()
                    .join(" | "),
                menu.selected
            ),
        );
    }

    /// 每拍：节流落盘 + 片尾提示 + 字幕菜单刷新。
    fn sync_playback(&self) {
        let snapshot = self.snapshot();
        self.refresh_subtitle_menu(&snapshot);
        if !snapshot.loaded {
            return;
        }
        let (position, duration) = (snapshot.position_ms(), snapshot.duration_ms());
        let now = now_ms();
        let prompt = {
            let mut guard = match self.page.lock() {
                Ok(guard) => guard,
                Err(poisoned) => poisoned.into_inner(),
            };
            match guard.as_mut() {
                Some(page) => self.with_library(|library| {
                    page.tick(library, position, duration, &self.policy, now)
                }),
                None => false,
            }
        };
        if prompt {
            if let Some(ui) = self.ui.upgrade() {
                ui.set_outro_visible(true);
                ui.set_outro_text("片尾 · 跳过".into());
            }
            self.log.write(
                "info",
                &format!("playback: 到片尾（{position}ms），提示一次"),
            );
            self.shared.touch();
        }
    }

    /// 关窗 / 换片 / 退出前落盘（看完写 0，下次从头）。
    fn flush_current_progress(&self) {
        let snapshot = self.snapshot();
        let (position, duration) = (snapshot.position_ms(), snapshot.duration_ms());
        let now = now_ms();
        let guard = match self.page.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        let Some(page) = guard.as_ref() else { return };
        match self
            .with_library(|library| page.flush(library, position, duration, &self.policy, now))
        {
            Ok(()) => self.log.write(
                "info",
                &format!("playback: 进度落盘 position={position}ms duration={duration:?}"),
            ),
            Err(err) => self
                .log
                .write("warn", &format!("playback: 进度落盘失败 {err}")),
        }
    }
    fn tick(self: &Rc<Self>) {
        let tick_index = self.ticks.fetch_add(1, Ordering::SeqCst) + 1;
        if tick_index.is_multiple_of(100) {
            self.log.write("info", &format!("tick: n={tick_index}"));
        }
        self.poll_playback();
        self.sync_playback();

        // 长按加速：按住够久由 0.1s tick 触发（鼠标静止时没有移动事件可用），
        // 松手在 hit.rs 里结束。只进一次，避免每拍重复设置。
        if self.shared.press_boost_due() {
            self.set_speed_boost(true);
        }

        let layout = self.layout_from_slint();
        if let Ok(mut slot) = self.shared.layout.lock() {
            *slot = layout;
        }

        self.ensure_overlay();
        self.publish_state(&layout);
        self.maybe_sample();
        self.selftest_step();
    }

    /// 用属性轮询代替 mpv 事件队列（M1 不跑 wait_event，主线程只读属性）。
    fn poll_playback(&self) {
        let snapshot = self.snapshot();
        let playing = self.playing.load(Ordering::SeqCst);

        if snapshot.loaded && !self.saw_loaded.swap(true, Ordering::SeqCst) {
            self.playing.store(true, Ordering::SeqCst);
            self.log.write("info", "ui: 检测到已加载，开始采样探针");
            if let Some(ui) = self.ui.upgrade()
                && let Some(path) = self.autoplay.as_ref()
            {
                ui.set_media_title(file_stem(path).into());
            }
            self.apply_start_plan();
            self.apply_default_subtitle(&snapshot);
            self.try_hdr_csp();
            self.sample();
            return;
        }

        if playing && snapshot.eof_reached {
            self.playing.store(false, Ordering::SeqCst);
            self.log.write("info", "playback: end reason=eof");
            self.log
                .write("info", "ui: 播放到结尾（keep-open 停在最后一帧）");
        }
    }

    /// 定位宿主窗口 → show 叠层 → 透明加固 → 挂子窗口 → 装输入监视器。
    fn ensure_overlay(self: &Rc<Self>) {
        // 先请求播放，mpv 才会建自己的窗口（不再 force-window）—— 然后下面去定位它
        if !self.load_requested.load(Ordering::SeqCst)
            && let Some(path) = self.autoplay.clone()
        {
            self.load_requested.store(true, Ordering::SeqCst);
            self.open_media(path);
        }

        // 已经挂好了就只跟 frame（子窗口不随父窗口 resize/全屏自动改尺寸）
        if let Some(handle) = self.overlay_handle() {
            overlay::sync_frame(&handle.overlay, &handle.host);
            // 只在宿主 frame 真的变了时写一行（子窗口的取整差异会让 setFrame 反复触发，
            // 之前每 100ms 一行把 m1.log 刷到上万行）
            let host = overlay::frame(&handle.host);
            let changed = self
                .last_logged_frame
                .lock()
                .map(|last| match *last {
                    Some((x, y, w, h)) => {
                        (host.0 - x).abs() > 1.0
                            || (host.1 - y).abs() > 1.0
                            || (host.2 - w).abs() > 1.0
                            || (host.3 - h).abs() > 1.0
                    }
                    None => true,
                })
                .unwrap_or(true);
            if changed {
                if let Ok(mut last) = self.last_logged_frame.lock() {
                    *last = Some(host);
                }
                self.log.write(
                    "info",
                    &format!(
                        "overlay: frame 跟随宿主 → {{{:.0},{:.0} {:.0}x{:.0}}}",
                        host.0, host.1, host.2, host.3
                    ),
                );
            }
            return;
        }

        let Some(host) = host_window::find_host_window() else {
            // 还没有 mpv 窗口：先把壳自己显示出来（用户要能看见界面、点「打开文件」）
            self.show_standalone_shell();
            let tries = self.locate_tries.fetch_add(1, Ordering::SeqCst) + 1;
            let due = self
                .last_scan_diag_at
                .lock()
                .map(|last| last.elapsed() >= Duration::from_millis(1000))
                .unwrap_or(true);
            if due {
                if let Ok(mut last) = self.last_scan_diag_at.lock() {
                    *last = Instant::now();
                }
                self.log.write(
                    "warn",
                    &format!(
                        "{} | shell=standalone（未退出，等 mpv 窗口出现）| try={tries}",
                        host_window::windows_diagnostic_line(
                            &host_window::list_detailed(),
                            host_window::screen_locked()
                        )
                    ),
                );
            }
            if tries == LOCATE_TRIES && self.load_requested.load(Ordering::SeqCst) {
                self.log.write(
                    "warn",
                    &format!(
                        "E4004: 定位宿主窗口失败（按 class=swift.Window 扫了 {tries} 次）。已知降级：叠层作独立浮动窗口。"
                    ),
                );
            }
            return;
        };

        // 宿主要接受 mouseMoved，否则指针在画面区时我们收不到事件
        host_window::set_accepts_mouse_moved(&host, true);

        // 先把 Slint 窗口的逻辑尺寸对齐宿主窗口，再 show（否则两套尺寸会互相扯）
        let host_frame = host_window::frame(&host);
        if let Some(ui) = self.ui.upgrade() {
            ui.window().set_size(slint::LogicalSize::new(
                host_frame.w as f32,
                host_frame.h as f32,
            ));
        }

        if !self.shown.swap(true, Ordering::SeqCst)
            && let Some(ui) = self.ui.upgrade()
        {
            match ui.show() {
                Ok(()) => self
                    .log
                    .write("info", "ui: Slint 窗口已 show（no-frame + transparent）"),
                Err(err) => {
                    self.log.write("warn", &format!("ui: show 失败 {err}"));
                    return;
                }
            }
        }

        let Some(overlay_window) = overlay::find_overlay_window() else {
            return;
        };

        self.log.write(
            "info",
            &format!(
                "window: 候选窗口 {}",
                host_window::list()
                    .iter()
                    .map(|info| format!(
                        "\n  - title=\"{}\" class={} #{} {}",
                        info.title, info.class, info.number, info.frame
                    ))
                    .collect::<Vec<_>>()
                    .join("")
            ),
        );
        self.log.write(
            "info",
            &format!(
                "window: 找到宿主窗口 title=\"{}\" class={} #{} {}",
                host_window::title(&host),
                host_window::class_name(&host),
                host.windowNumber(),
                host_window::frame(&host),
            ),
        );

        let report = overlay::attach(&overlay_window, &host);
        self.log.write("info", &report.log_line());
        self.log.write(
            "info",
            &format!(
                "window: 叠层 class={} #{}，标题={} / 宿主标题={}",
                overlay::window_class(&overlay_window),
                overlay_window.windowNumber(),
                OVERLAY_WINDOW_TITLE,
                HOST_WINDOW_TITLE,
            ),
        );

        let screen = host_window::screen_edr(&host);
        self.log.write(
            "info",
            &format!(
                "screen: name=\"{}\" potentialEDR={:.3} currentEDR={:.3} scale={:.2}",
                screen.name, screen.max_potential_edr, screen.max_current_edr, screen.scale
            ),
        );

        let sink: Rc<dyn InputSink> = self.clone();
        let monitor = hit::install(
            host.clone(),
            overlay_window.clone(),
            self.shared.clone(),
            sink,
        );
        match &monitor {
            Some(_) => self
                .log
                .write("info", "input: NSEvent local monitor 已装（键盘单一主人）"),
            None => self
                .log
                .write("warn", "input: NSEvent local monitor 安装失败"),
        }
        if let Ok(mut slot) = self.monitor.lock() {
            *slot = monitor;
        }
        self.store_overlay(OverlayHandle {
            overlay: overlay_window,
            host: host.clone(),
        });

        // 播放已经在定位窗口之前请求过，这里不再触发
    }

    /// 独立壳窗口：没有宿主窗口时也能看到界面（HLD §9.6 的温和降级）。
    fn show_standalone_shell(&self) {
        if self.standalone.swap(true, Ordering::SeqCst) {
            return;
        }
        let Some(ui) = self.ui.upgrade() else { return };
        if !self.shown.swap(true, Ordering::SeqCst) {
            match ui.show() {
                Ok(()) => self.log.write(
                    "info",
                    "ui: 还没有 mpv 窗口 → 壳先独立显示（1200x760），打开文件后再收成子窗口",
                ),
                Err(err) => {
                    self.log.write("warn", &format!("ui: show 失败 {err}"));
                    return;
                }
            }
        }
        if let Some(window) = overlay::find_overlay_window() {
            let (style_mask, opaque) = overlay::configure_standalone(&window);
            let frame = overlay::frame(&window);
            self.log.write(
                "info",
                &format!(
                    "ui: 独立壳 window=#{} styleMask=0x{:x} opaque={} frame={{{:.0},{:.0} {:.0}x{:.0}}}",
                    window.windowNumber(),
                    style_mask,
                    opaque,
                    frame.0,
                    frame.1,
                    frame.2,
                    frame.3
                ),
            );
        }
    }

    fn publish_state(&self, layout: &hit::Layout) {
        let Some(ui) = self.ui.upgrade() else { return };
        let idle = self.shared.idle();
        let (pointer_x, pointer_y) = self.shared.pointer();
        let playing = self.playing.load(Ordering::SeqCst);
        let fullscreen = self
            .overlay
            .lock()
            .ok()
            .and_then(|guard| {
                guard
                    .as_ref()
                    .map(|handle| host_window::is_fullscreen(&handle.host))
            })
            .unwrap_or(false);

        let pointer_at_top = pointer_y <= layout.top_edge;
        let header = hit::header_visible(playing, fullscreen, idle, pointer_at_top);
        let controls = hit::controls_visible(idle);
        let traffic = hit::traffic_visible(fullscreen, idle, pointer_x, pointer_y, layout);

        if let Ok(mut flags) = self.shared.flags.lock() {
            *flags = Flags {
                playing,
                fullscreen,
                header_visible: header,
                controls_visible: controls,
                probe_visible: ui.get_probe_visible(),
            };
        }

        ui.set_playing(playing);
        ui.set_fullscreen(fullscreen);
        ui.set_header_visible(header);
        ui.set_controls_visible(controls);
        ui.set_traffic_visible(traffic);

        let snapshot = self.snapshot();
        ui.set_clock_label(clock_label(snapshot.time_pos, snapshot.duration).into());
        if let (Some(position), Some(duration)) = (snapshot.time_pos, snapshot.duration)
            && duration > 0.0
        {
            ui.set_progress((position / duration).clamp(0.0, 1.0) as f32);
        }
        // 状态行不许写死 headroom：本机 potentialEDR = 2.000、currentEDR = 1.000
        let screen_state = self
            .last_screen_state
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_default();
        ui.set_status_line(
            format!(
                "M1 · {} · EDR headroom {:.2}（潜力 {:.2}）",
                if playing { "播放中" } else { "待播放" },
                screen_state.max_current_edr,
                screen_state.max_potential_edr
            )
            .into(),
        );
    }

    /// 源是 PQ/HLG 就把输出 csp 打开（HLD §5.3 的实测项，只做一次）。
    fn try_hdr_csp(&self) {
        if self.hdr_csp_sent.swap(true, Ordering::SeqCst) {
            return;
        }
        let snapshot = self.snapshot();
        let gamma = snapshot.source_gamma.clone();
        if seewow_player::probe::is_pq_or_hlg(&gamma) {
            self.log.write(
                "info",
                &format!("csp: 源是 HDR（gamma={gamma}），请求输出 bt.2100-pq"),
            );
            self.host.set_output_csp("bt.2100-pq");
        } else {
            self.log.write(
                "info",
                &format!("csp: 源不是 PQ/HLG（gamma={gamma}），输出保持 auto"),
            );
        }
    }

    fn maybe_sample(&self) {
        // 不播放时也采样：面板要能显示屏幕 EDR 与判定（本机 SDR 屏的证据就这么来）
        let due = self
            .last_probe_at
            .lock()
            .map(|last| last.elapsed() >= Duration::from_millis(250))
            .unwrap_or(true);
        if !due {
            return;
        }
        if let Ok(mut last) = self.last_probe_at.lock() {
            *last = Instant::now();
        }
        self.sample();
    }

    fn sample(&self) {
        let handle = self.overlay_handle();
        let snapshot = self.snapshot();
        // 没有宿主窗口时也要能出数：mpv 侧来自快照，macOS 侧读主屏（图层一栏为 n/a）
        let (layer, screen) = match handle.as_ref() {
            Some(handle) => (
                host_window::layer_state(&handle.host, &snapshot.csp),
                host_window::screen_edr(&handle.host),
            ),
            None => (
                seewow_player::probe::LayerState::default(),
                host_window::screen_edr_main(),
            ),
        };
        let seed = ProbeSeed {
            target: snapshot.target.clone(),
            layer,
            screen,
            pixel_readback_max: None,
        };
        let verdict = judge(&seed);

        // 屏幕状态留一份给状态行（不许把 headroom 写死）
        if let Ok(mut last) = self.last_screen_state.lock() {
            *last = seed.screen.clone();
        }

        // **证据先落盘，UI 后更新**：面板拿不到也必须有 target.*（评审 P0-2）
        let key = format!(
            "{}|{}|{}|{}|{}|{}|{}|{:.3}|{:.3}|{}|{}",
            dash(&seed.target.gamma),
            dash(&seed.target.primaries),
            seed.target
                .max_luma
                .map(|v| format!("{v:.1}"))
                .unwrap_or_else(|| "n/a".into()),
            dash(&seed.target.pixelformat),
            dash(&seed.layer.pixel_format),
            seed.layer.wants_edr,
            dash(&seed.layer.colorspace),
            seed.screen.max_potential_edr,
            seed.screen.max_current_edr,
            verdict.pipeline_hdr,
            verdict.on_screen_hdr,
        );
        let changed = self
            .last_probe_key
            .lock()
            .map(|last| *last != key)
            .unwrap_or(true);
        let since_last = self
            .last_probe_log_at
            .lock()
            .map(|last| last.elapsed())
            .unwrap_or(Duration::from_secs(3600));
        let playing = self.playing.load(Ordering::SeqCst);
        if seewow_player::probe::should_log_probe(playing, changed, since_last) {
            if let Ok(mut last) = self.last_probe_log_at.lock() {
                *last = Instant::now();
            }
            if let Ok(mut last) = self.last_probe_key.lock() {
                *last = key;
            }
            self.log.write(
                "info",
                &seewow_player::probe::probe_log_line(&seed, &snapshot.source, &verdict),
            );
        }

        // 屏变了单独记一行（换屏不崩的证据）
        let previous_screen = self
            .last_screen
            .lock()
            .map(|s| s.clone())
            .unwrap_or_default();
        if previous_screen != seed.screen.name {
            if let Ok(mut last) = self.last_screen.lock() {
                *last = seed.screen.name.clone();
            }
            self.log.write(
                "info",
                &format!(
                    "screen: 屏幕（重新）读取 → name=\"{}\" potentialEDR={:.3} currentEDR={:.3}",
                    seed.screen.name, seed.screen.max_potential_edr, seed.screen.max_current_edr
                ),
            );
        }

        // target.* 不可用时写清原因（不存在 / 存在但为空 / 锁屏属预期），5 秒最多一条
        if seed.target.gamma.trim().is_empty() || seed.target.gamma.trim() == "n/a" {
            let due = self
                .last_target_diag_at
                .lock()
                .map(|last| last.elapsed() >= Duration::from_millis(5000))
                .unwrap_or(true);
            if due {
                if let Ok(mut last) = self.last_target_diag_at.lock() {
                    *last = Instant::now();
                }
                self.log.write(
                    "warn",
                    &seewow_player::probe::target_unavailable_note(
                        &snapshot.vo,
                        host_window::screen_locked(),
                    ),
                );
            }
        }

        // 面板更新（拿不到 UI 就直接跳过，绝不影响上面已经写好的证据）
        let Some(ui) = self.ui.upgrade() else { return };
        ui.set_probe_mpv(snapshot.rows.clone().into());
        ui.set_probe_mac(seewow_player::probe::mac_rows(&seed).into());
        ui.set_probe_verdict(verdict_rows(&verdict).into());
        ui.set_probe_headline(verdict.headline.clone().into());
        ui.set_probe_pipeline(verdict.pipeline_hdr);
        ui.set_probe_onscreen(verdict.on_screen_hdr);
    }

    fn selftest_step(&self) {
        if !self.selftest {
            return;
        }
        let elapsed = self.started.elapsed().as_millis() as u64;
        let step = self.selftest_step.load(Ordering::SeqCst);
        if step == 0 && elapsed > 2500 && self.playing.load(Ordering::SeqCst) {
            self.log.write("info", "SELFTEST: step 1 全屏进入");
            self.toggle_fullscreen();
            self.selftest_step.store(1, Ordering::SeqCst);
        } else if step == 1 && elapsed > 7000 {
            self.log.write("info", "SELFTEST: step 2 全屏退出");
            self.toggle_fullscreen();
            self.selftest_step.store(2, Ordering::SeqCst);
        } else if step == 2 && elapsed > 11000 {
            self.log.write("info", "SELFTEST: step 3 关闭");
            self.selftest_step.store(3, Ordering::SeqCst);
            self.shutdown();
        }
    }

    fn open_file_dialog(self: &Rc<Self>) {
        use objc2_app_kit::NSOpenPanel;

        let Some(mtm) = objc2::MainThreadMarker::new() else {
            self.log.write("warn", "ui: NSOpenPanel 只能在主线程打开");
            return;
        };
        let panel = NSOpenPanel::openPanel(mtm);
        panel.setCanChooseDirectories(false);
        panel.setAllowsMultipleSelection(false);
        // NSModalResponseOK == 1
        if panel.runModal() != 1 {
            return;
        }
        let Some(url) = panel.URL() else { return };
        let Some(path) = url.path() else { return };
        let path = PathBuf::from(path.to_string());
        self.log.write(
            "info",
            &format!(
                "ui: 选了文件 {}",
                path.file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_default()
            ),
        );
        self.open_media(path);
    }

    fn toggle_fullscreen(&self) {
        if let Some(handle) = self.overlay_handle() {
            host_window::toggle_fullscreen(&handle.host);
            let now = host_window::is_fullscreen(&handle.host);
            self.log.write(
                "info",
                &format!("fullscreen: 已发出 toggleFullScreen，styleMask fullScreen={now}"),
            );
        }
    }

    fn shutdown(&self) {
        if self.shutdown_done.swap(true, Ordering::SeqCst) {
            return;
        }
        self.log.write(
            "info",
            "app: shutdown begin（叠层先 orderOut，再对 mpv 发 quit）",
        );
        // 先把进度写进库：关窗不该丢最后一次位置。
        self.flush_current_progress();
        if let Some(handle) = self.overlay_handle() {
            overlay::order_out(&handle.overlay);
            overlay::detach_child(&handle.host, &handle.overlay);
        }
        self.host.quit();
        let _ = slint::quit_event_loop();
        self.log.write("info", "app: shutdown done");
    }
}

impl InputSink for Core {
    fn toggle_pause(&self) {
        let paused = self.host.toggle_pause();
        let playing = !paused;
        self.playing.store(playing, Ordering::SeqCst);
        if let Some(ui) = self.ui.upgrade() {
            ui.set_playing(playing);
        }
        self.log
            .write("info", &format!("playback: 切换 pause={paused}"));
        self.shared.touch();
    }

    fn toggle_fullscreen(&self) {
        Core::toggle_fullscreen(self);
        self.shared.touch();
    }

    fn request_shutdown(&self) {
        self.shutdown();
    }

    fn minimize(&self) {
        if let Some(handle) = self.overlay_handle() {
            host_window::miniaturize(&handle.host);
            self.log.write("info", "window: 最小化（Cmd+M）");
        }
    }

    fn seek_by_step(&self, direction: i8) {
        // 步长来自 core::Keymap（默认 10 秒）；这一层只认方向，不写死数字。
        let step = seewow_core::Keymap::default().seek_step_ms * i64::from(direction.signum());
        self.host.player().seek_relative_ms(step);
        self.log
            .write("info", &format!("playback: 手势/键盘跳转 {step} ms"));
        self.shared.touch();
    }

    fn set_speed_boost(&self, on: bool) {
        let player = self.host.player();
        if on {
            let current = self.snapshot().speed;
            let base = if (current - 1.0).abs() < f64::EPSILON || current <= 0.0 {
                1.0
            } else {
                current
            };
            if let Ok(mut slot) = self.base_speed.lock() {
                *slot = base;
            }
            let boost = seewow_core::Keymap::default().hold_speed;
            player.set_speed(boost);
            self.log.write(
                "info",
                &format!("gesture: 长按加速 {boost:.1}x（原速 {base:.2}x）"),
            );
        } else {
            let base = self.base_speed.lock().map(|v| *v).unwrap_or(1.0);
            player.set_speed(base);
            self.log
                .write("info", &format!("gesture: 松手，恢复 {base:.2}x"));
        }
        self.shared.touch();
    }

    fn note_activity(&self) {
        self.shared.touch();
    }
}

fn file_stem(path: &std::path::Path) -> String {
    path.file_stem()
        .map(|stem| stem.to_string_lossy().to_string())
        .unwrap_or_else(|| "SeeWow".to_string())
}

fn dash(value: &str) -> &str {
    if value.trim().is_empty() {
        "n/a"
    } else {
        value.trim()
    }
}

fn verdict_rows(verdict: &Verdict) -> String {
    let mut out = String::new();
    for check in &verdict.checks {
        out.push_str(if check.ok { "✓ " } else { "✗ " });
        out.push_str(check.label);
        out.push('\n');
    }
    out.push_str(&format!("\nevidence_source {}\n", verdict.evidence_source));
    out.push_str(if verdict.evidence_source == 1 {
        "= 像素回读"
    } else {
        "= 管线状态（非像素回读）"
    });
    out
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

/// 打开片库。打不开就返回 None：能播，只是没有续播与片头片尾。
fn open_library(log: &M1Log) -> Option<Library> {
    let paths = match Paths::discover() {
        Ok(paths) => paths,
        Err(err) => {
            log.write(
                "warn",
                &format!("library: 找不到应用数据目录（{err}），本次没有续播"),
            );
            return None;
        }
    };
    if let Err(err) = paths.ensure() {
        log.write("warn", &format!("library: 建目录失败（{err}）"));
    }
    let database = paths.library_db();
    match Library::open(&database) {
        Ok(library) => {
            let count = library.count_media().unwrap_or(0);
            log.write(
                "info",
                &format!("library: 已打开 {}（{count} 条）", database.display()),
            );
            Some(library)
        }
        Err(err) => {
            log.write("warn", &format!("library: 打开失败（{err}），本次没有续播"));
            None
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    // 命令行分支必须在 Slint / mpv / 日志初始化之前：--scan 不需要窗口。
    let autoplay = match cli::parse_args(&args) {
        Ok(cli::Command::Gui { autoplay }) => autoplay.filter(|path| path.exists()),
        Ok(cli::Command::Help) => {
            print!("{}", cli::USAGE);
            return;
        }
        Ok(cli::Command::Scan {
            root,
            json,
            include_hidden,
            db,
        }) => std::process::exit(cli::run_scan(&root, json, include_hidden, db.as_deref())),
        Err(message) => {
            eprintln!("{message}\n\n{}", cli::USAGE);
            std::process::exit(2);
        }
    };
    let selftest = std::env::var("SEEWOW_SELFTEST")
        .map(|value| value == "1")
        .unwrap_or(false);

    let log = Arc::new(M1Log::open().expect("~/Library/Logs/SeeWow/m1.log 打不开"));

    // panic 必须留下痕迹：事件循环里的回调 panic 会被上层吞掉，看不到就等于没有（HLD §8.4）
    {
        let log = log.clone();
        std::panic::set_hook(Box::new(move |info| {
            log.write("error", &format!("panic: {info}"));
        }));
    }

    log.write(
        "info",
        &format!(
            "app: start version={} arch={} autoplay={:?} selftest={} log={}",
            env!("CARGO_PKG_VERSION"),
            std::env::consts::ARCH,
            autoplay
                .as_ref()
                .and_then(|path| path.file_name().map(|n| n.to_string_lossy().to_string())),
            selftest,
            log.path().display(),
        ),
    );

    // 让本进程成为「普通前台 App」并激活：mpv 的窗口/CAMetalLayer 需要 app 真的在前台，
    // 否则它的 present 会一直等（实测：非激活状态下 mpv 的 vo 线程卡在 swapBuffer）。
    if let Some(mtm) = objc2::MainThreadMarker::new() {
        use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy};
        let app = NSApplication::sharedApplication(mtm);
        app.setActivationPolicy(NSApplicationActivationPolicy::Regular);
        app.activate();
        log.write("info", "app: activationPolicy=Regular 并已 activate");
    }

    let shell = Shell::new().expect("Slint 组件创建失败");
    log.write("info", "app: Slint 组件已创建（尚未 show）");

    let host = Arc::new(PlayerHost::start(log.clone()).expect("libmpv 初始化失败"));

    // V1 证据：此刻 NSApp.windows 里有什么（mpv 的窗口要等主线程 dispatch 之后才出现）
    let pre_windows = host_window::list();
    log.write(
        "info",
        &format!(
            "window: 启动时窗口数={} {:?}",
            pre_windows.len(),
            pre_windows
                .iter()
                .map(|info| (info.title.clone(), info.class.clone()))
                .collect::<Vec<_>>()
        ),
    );

    let library = open_library(&log);

    let core = Rc::new(Core {
        log: log.clone(),
        host: host.clone(),
        ui: shell.weak(),
        shared: hit::Shared::new(),
        overlay: Mutex::new(None),
        monitor: Mutex::new(None),
        autoplay,
        library: Mutex::new(library),
        policy: ResumePolicy::default(),
        prefs: PlayerPreferences::default(),
        page: Mutex::new(None),
        pending_seek_ms: Mutex::new(None),
        last_subtitle_state: Mutex::new(None),
        base_speed: Mutex::new(1.0),
        locate_tries: AtomicU32::new(0),
        load_requested: AtomicBool::new(false),
        shown: AtomicBool::new(false),
        standalone: AtomicBool::new(false),
        playing: AtomicBool::new(false),
        saw_loaded: AtomicBool::new(false),
        hdr_csp_sent: AtomicBool::new(false),
        shutdown_done: AtomicBool::new(false),
        last_probe_at: Mutex::new(Instant::now() - Duration::from_secs(1)),
        last_probe_log_at: Mutex::new(Instant::now() - Duration::from_secs(1)),
        last_screen: Mutex::new(String::new()),
        last_snapshot: Mutex::new(seewow_player::host::MpvSnapshot::default()),
        last_screen_state: Mutex::new(seewow_player::probe::ScreenState::default()),
        last_logged_frame: Mutex::new(None),
        last_probe_key: Mutex::new(String::new()),
        last_scan_diag_at: Mutex::new(Instant::now() - Duration::from_secs(10)),
        last_target_diag_at: Mutex::new(Instant::now() - Duration::from_secs(10)),
        selftest,
        selftest_step: AtomicU32::new(0),
        ticks: AtomicU32::new(0),
        started: Instant::now(),
    });

    wire_callbacks(&shell, &core);

    // 0.1s 的 tick：定位窗口 / 对齐 frame / 推 UI 状态 / 采探针（主线程，永不调 libmpv）。
    //
    // 用 `NSTimer`（挂主 run loop）而不是 Slint 的 `Timer`：实测里 Slint 的 Repeated timer
    // 在本进程只触发一次就不再回来（winit 的唤醒路径和 mpv 的主线程 dispatch 打架），
    // 而 NSTimer 在同样环境下持续触发。驱动方式的选择记在 Q-02。
    {
        use objc2_foundation::NSTimer;

        let tick_core = core.clone();
        let block = block2::RcBlock::new(move |_timer: std::ptr::NonNull<NSTimer>| {
            tick_core.tick();
        });
        let timer =
            unsafe { NSTimer::scheduledTimerWithTimeInterval_repeats_block(0.1, true, &block) };
        std::mem::forget(timer);
        std::mem::forget(block);
    }

    log.write("info", "app: 进入 Slint 事件循环");
    if let Err(err) = slint::run_event_loop() {
        log.write("warn", &format!("app: 事件循环异常退出 {err}"));
    }
    core.shutdown();

    std::thread::sleep(Duration::from_millis(150));
    log.write("info", "app: exit");
    std::process::exit(0);
}

fn wire_callbacks(shell: &Shell, core: &Rc<Core>) {
    let ui = shell.ui();

    {
        let core = core.clone();
        ui.on_open_file(move || core.open_file_dialog());
    }
    {
        let core = core.clone();
        ui.on_seek_backward(move || InputSink::seek_by_step(core.as_ref(), -1));
    }
    {
        let core = core.clone();
        ui.on_seek_forward(move || InputSink::seek_by_step(core.as_ref(), 1));
    }
    {
        let core = core.clone();
        ui.on_cycle_speed(move || {
            let current = core.snapshot().speed;
            let steps = [0.5_f64, 0.75, 1.0, 1.25, 1.5, 2.0];
            let next = steps
                .iter()
                .copied()
                .find(|value| *value > current + 0.01)
                .unwrap_or(steps[0]);
            core.host.player().set_speed(next);
            if let Some(ui) = core.ui.upgrade() {
                ui.set_speed_label(format!("{next:.1}x").into());
            }
            core.log
                .write("info", &format!("ui: 循环倍速 {current:.2}x → {next:.2}x"));
            core.shared.touch();
        });
    }
    {
        let core = core.clone();
        // CC 改成开菜单（条目来自 mpv track-list），不再盲轮换。
        ui.on_toggle_subtitle(move || {
            if let Some(ui) = core.ui.upgrade() {
                let open = !ui.get_subtitle_menu_open();
                ui.set_subtitle_menu_open(open);
                core.log.write("info", &format!("ui: 字幕菜单 open={open}"));
            }
            core.shared.touch();
        });
    }
    {
        let core = core.clone();
        // 0 = 关；1..n = track-list 的第 n 条。
        ui.on_pick_subtitle(move |index| {
            let snapshot = core.snapshot();
            let menu =
                playback::subtitle_menu(&snapshot.subtitle_tracks, snapshot.selected_subtitle);
            let target = if index <= 0 {
                None
            } else {
                menu.items.get((index - 1) as usize).map(|item| item.id)
            };
            core.host.player().select_subtitle(target);
            if let Some(ui) = core.ui.upgrade() {
                ui.set_subtitle_menu_open(false);
            }
            core.log.write(
                "info",
                &format!(
                    "ui: 选字幕 track={target:?}（菜单 {} 条）",
                    menu.items.len()
                ),
            );
            core.shared.touch();
        });
    }
    {
        let core = core.clone();
        // 片尾「跳过」：拖到末尾。连播下一集属于 T-16（会话节拍），这里不抢。
        ui.on_outro_skip(move || {
            let snapshot = core.snapshot();
            match snapshot.duration {
                Some(duration) if duration > 0.0 => {
                    core.host.player().seek_absolute(duration);
                    core.log
                        .write("info", &format!("ui: 片尾 → 跳过，拖到 {duration:.3}s"));
                }
                _ => core.log.write("warn", "ui: 片尾跳过失败（mpv 还没报时长）"),
            }
            if let Some(ui) = core.ui.upgrade() {
                ui.set_outro_visible(false);
            }
            core.shared.touch();
        });
    }
    {
        let core = core.clone();
        ui.on_outro_dismiss(move || {
            if let Some(ui) = core.ui.upgrade() {
                ui.set_outro_visible(false);
            }
            core.log.write("info", "ui: 片尾提示已关闭（本集不再弹）");
            core.shared.touch();
        });
    }
    {
        let core = core.clone();
        ui.on_toggle_probe(move || {
            if let Some(ui) = core.ui.upgrade() {
                let next = !ui.get_probe_visible();
                ui.set_probe_visible(next);
                core.log
                    .write("info", &format!("ui: 探针面板 visible={next}"));
            }
            core.shared.touch();
        });
    }
    {
        let core = core.clone();
        ui.on_toggle_pause(move || core.toggle_pause());
    }
    {
        let core = core.clone();
        ui.on_toggle_fullscreen(move || Core::toggle_fullscreen(&core));
    }
    {
        let core = core.clone();
        ui.on_traffic_close(move || core.shutdown());
    }
    {
        let core = core.clone();
        ui.on_traffic_minimize(move || core.minimize());
    }
    {
        let core = core.clone();
        ui.on_traffic_zoom(move || Core::toggle_fullscreen(&core));
    }
}
