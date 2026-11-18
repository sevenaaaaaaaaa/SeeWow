//! 播放页接线（M3 · T-15）：起播点、片头片尾、字幕轨菜单、进度落盘。
//!
//! 这一层只做**决定**：不碰窗口，也不直接调 libmpv。`main.rs` 拿到这里的结论后
//! 再下发给 `Player` 与 UI。分成「决定层 / 接线层」是为了能脱离窗口验证
//! （tests/playback_wiring.rs 全是决定层的用例）。
//!
//! 三条复用纪律，一条也不新立：
//! 1. 起播点用 `seewow_core::ResumePolicy`（30 秒门槛 / 回退 3 秒 / 看完清空），
//!    本模块只决定「片头要不要盖过它」，不写第二个阈值；
//! 2. 片头片尾用 `seewow_library::chapters`（T-17 的存储），按 `show_key` 读，
//!    落库格式与清空语义都由那一层负责；
//! 3. 字幕轨来自 mpv 的 `track-list`（`TrackInfo`），不按文件名猜。

use std::path::Path;

use seewow_core::{
    MediaEntry, MediaId, Result, ResumePoint, ResumePolicy, TrackInfo, parse_file_name,
};
use seewow_library::{ChapterKind, Library, WatchState};

// ---------------------------------------------------------------- 片头片尾

/// 一部剧的片头/片尾标记（毫秒）。`None` = 没标过，不参与判断。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ChapterPlan {
    /// 片头结束的位置：起播点落在这之前就跳到这里。
    pub intro_end_ms: Option<i64>,
    /// 片尾开始的位置：到这里提示「跳过片尾」。
    pub outro_start_ms: Option<i64>,
}

impl ChapterPlan {
    /// 丢掉没意义的片头标记：0、负值、超过片子本身。
    ///
    /// 用户手滑标错一个数不该让片子打不开——宁可从头播。
    fn usable_intro(&self, duration_ms: Option<i64>) -> Option<i64> {
        let intro = self.intro_end_ms?;
        if intro <= 0 {
            return None;
        }
        match duration_ms.filter(|duration| *duration > 0) {
            Some(duration) if intro >= duration => None,
            _ => Some(intro),
        }
    }
}

/// 读一部剧的标记；没有 `show_key`（电影、没扫进库的文件）就是空计划。
///
/// 片库读失败也返回空计划：播放不该因为一条标记读不出来就打不开。
pub fn load_chapter_plan(library: &Library, show_key: Option<&str>) -> ChapterPlan {
    let Some(show_key) = show_key.map(str::trim).filter(|key| !key.is_empty()) else {
        return ChapterPlan::default();
    };
    let Ok(marks) = library.chapter_marks(show_key) else {
        return ChapterPlan::default();
    };
    let mut plan = ChapterPlan::default();
    for mark in marks {
        match mark.kind {
            ChapterKind::IntroEnd => plan.intro_end_ms = Some(mark.position_ms),
            ChapterKind::OutroStart => plan.outro_start_ms = Some(mark.position_ms),
        }
    }
    plan
}

/// 到片尾了要不要提示。`already_prompted` 保证同一个位置只提示一次。
pub fn should_prompt_outro(
    position_ms: i64,
    chapters: &ChapterPlan,
    already_prompted: bool,
) -> bool {
    if already_prompted {
        return false;
    }
    match chapters.outro_start_ms {
        Some(outro) if outro > 0 => position_ms >= outro,
        _ => false,
    }
}

// ---------------------------------------------------------------- 起播点

/// 为什么从这个位置起播（日志与 UI 都要能说明白）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StartReason {
    /// 从头播（没看过、或进度不到门槛）。
    FromStart,
    /// 接着上次的位置（已经回退过 `rewind_ms`）。
    Resumed,
    /// 上次看完了：从头播。
    Finished,
    /// 起播点落在片头里，直接跳到片头结束。
    IntroSkipped,
}

impl StartReason {
    pub fn as_str(self) -> &'static str {
        match self {
            StartReason::FromStart => "from_start",
            StartReason::Resumed => "resumed",
            StartReason::Finished => "finished",
            StartReason::IntroSkipped => "intro_skipped",
        }
    }
}

/// 一次起播决定：落到哪里、为什么。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StartPlan {
    pub start_ms: i64,
    pub reason: StartReason,
}

/// 起播点：先问 `ResumePolicy`，再让片头盖过去。
///
/// 片头优先于续播的原因：续播点常常落在片头里（用户上次看了 40 秒就走了），
/// 这时候把镜头停在主题曲中间，比跳到片头结束更没意义。
pub fn plan_start(
    policy: &ResumePolicy,
    watch: Option<&WatchState>,
    duration_ms: Option<i64>,
    chapters: &ChapterPlan,
) -> StartPlan {
    let stored = watch.copied().unwrap_or_default();
    // 容器没报时长时用库里记的时长；两边都没有就交给 ResumePolicy 的「未知时长」分支。
    let duration = duration_ms
        .filter(|duration| *duration > 0)
        .or(stored.duration_ms.filter(|duration| *duration > 0));
    let intro_end = chapters.usable_intro(duration);
    // 没有进度记录就谈不上「看完」：短视频（不足 watched_tail_ms）的 0 秒位置
    // 会被「距结尾很近」判成已看完，那是误判——用户根本没看过。
    let point = if stored.position_ms > 0 {
        policy.resume_point(stored.position_ms, duration)
    } else {
        ResumePoint::FromStart
    };

    match point {
        ResumePoint::Finished => StartPlan {
            start_ms: 0,
            reason: StartReason::Finished,
        },
        ResumePoint::Continue { position_ms } => match intro_end {
            Some(end) if position_ms < end => StartPlan {
                start_ms: end,
                reason: StartReason::IntroSkipped,
            },
            _ => StartPlan {
                start_ms: position_ms,
                reason: StartReason::Resumed,
            },
        },
        ResumePoint::FromStart => match intro_end {
            Some(end) => StartPlan {
                start_ms: end,
                reason: StartReason::IntroSkipped,
            },
            None => StartPlan {
                start_ms: 0,
                reason: StartReason::FromStart,
            },
        },
    }
}

// ---------------------------------------------------------------- 认条目

/// 一个文件的身份：稳定 ID + 片头片尾用的 `show_key`。
///
/// `show_key` 为 `None` 表示「这部片不参与片头片尾」（电影、或名字里认不出剧名）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaKey {
    pub id: MediaId,
    pub show_key: Option<String>,
}

/// 认条目：先按**路径后缀**匹配片库（`/Volumes/Media/Shows/Dark/S01E01.mkv` 对上
/// 相对路径 `Shows/Dark/S01E01.mkv`），认不出来就用路径本身生成一个稳定 ID。
///
/// 为什么用后缀而不是全等：片库存的是相对路径，用户是从 Finder 里给绝对路径的。
pub fn media_key_for(path: &Path, entries: &[MediaEntry]) -> MediaKey {
    match entries
        .iter()
        .find(|entry| ends_with(path, &entry.relative_path))
    {
        Some(entry) => MediaKey {
            id: entry.id,
            show_key: normalize_show_key(entry.show_title.as_deref())
                .or_else(|| parsed_show_key(path)),
        },
        None => MediaKey {
            id: MediaId::from_parts("local", &path.to_string_lossy()),
            show_key: parsed_show_key(path),
        },
    }
}

/// 路径是否以相对路径结尾（按组件比，不是按字符串比：`S01E01` 不该对上 `S01E012`）。
fn ends_with(path: &Path, relative: &Path) -> bool {
    let absolute: Vec<_> = path.components().collect();
    let relative: Vec<_> = relative.components().collect();
    !relative.is_empty()
        && absolute.len() >= relative.len()
        && absolute[absolute.len() - relative.len()..] == relative[..]
}

/// 剧名归一化：去首尾空白、内部连续空白压成一个、转小写。
///
/// 「The  Office」与「the office」必须落到同一条标记上，否则用户得为同一部剧标两次。
fn normalize_show_key(show_title: Option<&str>) -> Option<String> {
    let title = show_title?;
    let normalized = title
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    if normalized.is_empty() {
        None
    } else {
        Some(normalized)
    }
}

/// 没扫进库的文件：从文件名里认剧名（`The Office S02E03.mkv` → `the office`）。
fn parsed_show_key(path: &Path) -> Option<String> {
    let stem = path.file_stem()?.to_string_lossy().to_string();
    let parent = path
        .parent()
        .and_then(Path::file_name)
        .map(|name| name.to_string_lossy().to_string());
    let parsed = parse_file_name(&stem, parent.as_deref());
    normalize_show_key(parsed.show_title.as_deref())
}

// ---------------------------------------------------------------- 字幕轨

/// 字幕菜单的一项。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubtitleItem {
    pub id: i64,
    /// 菜单上显示的文本：标题优先，其次语言标签，都没有就显示轨道号。
    pub label: String,
    pub language: Option<String>,
}

/// 字幕菜单：条目 + 当前选中 + 控制条上那个短标签。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SubtitleMenu {
    pub items: Vec<SubtitleItem>,
    pub selected: Option<i64>,
    /// 控制条 CC 按钮上的字：「CC 2/3」，关掉时是「CC 关」。
    pub summary: String,
}

/// 用 mpv `track-list` 里的字幕轨做菜单。**不做任何文件名猜测。**
pub fn subtitle_menu(tracks: &[TrackInfo], selected: Option<i64>) -> SubtitleMenu {
    let items: Vec<SubtitleItem> = tracks
        .iter()
        .map(|track| SubtitleItem {
            id: track.id,
            label: track_label(track),
            language: track.language.clone(),
        })
        .collect();
    // 选中的轨道可能已经随着换片消失：这时报「关」，但不改调用方记住的选择。
    let index = selected.and_then(|id| items.iter().position(|item| item.id == id));
    let summary = match index {
        Some(position) => format!("CC {}/{}", position + 1, items.len()),
        None => "CC 关".to_string(),
    };
    SubtitleMenu {
        selected: index.map(|position| items[position].id),
        summary,
        items,
    }
}

fn track_label(track: &TrackInfo) -> String {
    if let Some(title) = track
        .title
        .as_deref()
        .map(str::trim)
        .filter(|title| !title.is_empty())
    {
        return title.to_string();
    }
    if let Some(language) = track
        .language
        .as_deref()
        .map(str::trim)
        .filter(|language| !language.is_empty())
    {
        return language.to_string();
    }
    format!("#{}", track.id)
}

/// 轮换到下一字幕轨：关 → 第一条 → … → 最后一条 → 关。
///
/// 选中的轨道已经不在列表里（换片了）就从第一条重新开始，不卡死。
pub fn next_subtitle(tracks: &[TrackInfo], selected: Option<i64>) -> Option<i64> {
    let first = tracks.first()?;
    let Some(selected) = selected else {
        return Some(first.id);
    };
    match tracks.iter().position(|track| track.id == selected) {
        Some(position) => tracks.get(position + 1).map(|track| track.id),
        None => Some(first.id),
    }
}

// ---------------------------------------------------------------- 进度落盘

/// 读一条进度；没有记录就是默认值（`position_ms = 0`）。
///
/// 读失败也返回默认值：播放页不该因为一次 SQLite 读错误就进不去。
pub fn watch_state_of(library: &Library, id: MediaId) -> WatchState {
    library.watch_state(id).ok().flatten().unwrap_or_default()
}

/// 播放中落盘：按 `ResumePolicy::should_persist` 节流（前进 10 秒一次，回拖立刻写）。
///
/// 返回**新的**「上次落盘位置」；没写就原样返回，调用方直接存回去即可。
#[allow(clippy::too_many_arguments)]
pub fn persist_progress(
    library: &Library,
    id: MediaId,
    position_ms: i64,
    duration_ms: Option<i64>,
    policy: &ResumePolicy,
    last_persisted_ms: i64,
    now_ms: i64,
) -> Result<i64> {
    if !policy.should_persist(position_ms, last_persisted_ms) {
        return Ok(last_persisted_ms);
    }
    library.set_progress(id, position_ms, duration_ms, now_ms)?;
    Ok(position_ms)
}

/// 关窗/切片/换片时落盘：看完写 0（下次从头），否则写当前位置。
pub fn flush_progress(
    library: &Library,
    id: MediaId,
    position_ms: i64,
    duration_ms: Option<i64>,
    policy: &ResumePolicy,
    now_ms: i64,
) -> Result<()> {
    let position = policy.position_to_store(position_ms, duration_ms);
    library.set_progress(id, position, duration_ms, now_ms)
}

// ---------------------------------------------------------------- 会话

/// 一次播放会话：身份 + 片头片尾 + 上次进度。
///
/// `stored` 保留的是**库里那条原始进度**（没回退、没被片头改过），
/// 这样关窗时能写回真实位置，而不是写一个被策略改造过的数。
#[derive(Debug, Clone, PartialEq)]
pub struct SessionState {
    pub key: MediaKey,
    pub stored: WatchState,
    pub chapters: ChapterPlan,
}

impl SessionState {
    /// 打开一个文件：读进度、带片头片尾，进会话。
    pub fn begin(library: &Library, key: MediaKey, chapters: ChapterPlan) -> Self {
        let stored = watch_state_of(library, key.id);
        Self {
            key,
            stored,
            chapters,
        }
    }

    /// 这一次的起播点。
    pub fn plan(&self, policy: &ResumePolicy, duration_ms: Option<i64>) -> StartPlan {
        plan_start(
            policy,
            Some(&self.stored),
            duration_ms.or(self.stored.duration_ms),
            &self.chapters,
        )
    }
}

/// 播放页的接线状态：会话 + 落盘水位 + 片尾提示是否弹过。
#[derive(Debug, Clone, PartialEq)]
pub struct PlaybackPage {
    pub session: SessionState,
    /// 上次写库时的位置，节流用。
    pub last_persisted_ms: i64,
    /// 片尾提示只弹一次。
    pub outro_prompted: bool,
}

impl PlaybackPage {
    /// 打开一个文件（片库可以为空：没扫过库也能播，只是没有续播与片头片尾）。
    pub fn open(library: Option<&Library>, path: &Path) -> Self {
        let entries = library
            .and_then(|library| library.all_media().ok())
            .unwrap_or_default();
        let key = media_key_for(path, &entries);
        let chapters = match library {
            Some(library) => load_chapter_plan(library, key.show_key.as_deref()),
            None => ChapterPlan::default(),
        };
        let session = match library {
            Some(library) => SessionState::begin(library, key, chapters),
            None => SessionState {
                key,
                stored: WatchState::default(),
                chapters,
            },
        };
        Self {
            last_persisted_ms: session.stored.position_ms,
            outro_prompted: false,
            session,
        }
    }

    pub fn plan(&self, policy: &ResumePolicy, duration_ms: Option<i64>) -> StartPlan {
        self.session.plan(policy, duration_ms)
    }

    /// 每拍调一次：节流落盘，并给出「这次要不要提示片尾」。
    pub fn tick(
        &mut self,
        library: Option<&Library>,
        position_ms: i64,
        duration_ms: Option<i64>,
        policy: &ResumePolicy,
        now_ms: i64,
    ) -> bool {
        let duration = duration_ms.or(self.session.stored.duration_ms);
        if let Some(library) = library
            && let Ok(next) = persist_progress(
                library,
                self.session.key.id,
                position_ms,
                duration,
                policy,
                self.last_persisted_ms,
                now_ms,
            )
        {
            self.last_persisted_ms = next;
        }
        let prompt = should_prompt_outro(position_ms, &self.session.chapters, self.outro_prompted);
        if prompt {
            self.outro_prompted = true;
        }
        prompt
    }

    /// 关窗 / 换片 / 退出前落盘。
    pub fn flush(
        &self,
        library: Option<&Library>,
        position_ms: i64,
        duration_ms: Option<i64>,
        policy: &ResumePolicy,
        now_ms: i64,
    ) -> Result<()> {
        match library {
            Some(library) => flush_progress(
                library,
                self.session.key.id,
                position_ms,
                duration_ms.or(self.session.stored.duration_ms),
                policy,
                now_ms,
            ),
            None => Ok(()),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use seewow_core::{MediaKind, SourceKind};

    use super::*;

    const MINUTE: i64 = 60_000;

    fn temp_db(tag: &str) -> PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "seewow-page-{tag}-{}-{}.db",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = std::fs::remove_file(&path);
        path
    }

    fn entry(relative: &str, show: Option<&str>) -> MediaEntry {
        MediaEntry {
            id: MediaId::from_parts("local", relative),
            source_id: "local".to_string(),
            relative_path: PathBuf::from(relative),
            kind: if show.is_some() {
                MediaKind::Episode
            } else {
                MediaKind::Movie
            },
            title: relative.to_string(),
            show_title: show.map(str::to_string),
            year: Some(2017),
            season: Some(1),
            episode: Some(1),
            quality: "1080p".to_string(),
            added_at_ms: 1,
        }
    }

    /// 一条完整的「打开即播」路径：认条目 → 读片头片尾与上次进度 → 决定起播点。
    #[test]
    fn opening_a_scanned_episode_carries_marks_and_progress_into_the_plan() {
        let path = temp_db("open");
        let show = entry("Shows/Dark/S01E01.mkv", Some(" Dark "));
        {
            let mut library = Library::open(&path).unwrap();
            library
                .upsert_source("local", SourceKind::Local, "本地", "/", 1)
                .unwrap();
            library.upsert_media(std::slice::from_ref(&show)).unwrap();
            library
                .set_chapter_mark("dark", ChapterKind::IntroEnd, 85_000, 1)
                .unwrap();
            library
                .set_progress(show.id, 10 * MINUTE, Some(45 * MINUTE), 1)
                .unwrap();
        }

        let reopened = Library::open(&path).unwrap();
        let page = PlaybackPage::open(
            Some(&reopened),
            Path::new("/Volumes/Media/Shows/Dark/S01E01.mkv"),
        );
        assert_eq!(page.session.key.id, show.id);
        assert_eq!(page.session.key.show_key.as_deref(), Some("dark"));
        assert_eq!(
            page.session.chapters,
            ChapterPlan {
                intro_end_ms: Some(85_000),
                outro_start_ms: None
            }
        );
        // 10 分钟已经在片头之后：续播点不被片头盖掉。
        assert_eq!(
            page.plan(&ResumePolicy::default(), Some(45 * MINUTE))
                .start_ms,
            10 * MINUTE - 3_000
        );
        assert_eq!(page.last_persisted_ms, 10 * MINUTE);

        let _ = std::fs::remove_file(&path);
    }

    /// 没有片库也要能播：起播点从头，落盘全是空操作。
    #[test]
    fn a_page_without_a_library_still_decides_and_stays_quiet() {
        let mut page = PlaybackPage::open(None, Path::new("/tmp/loose.mkv"));
        let plan = page.plan(&ResumePolicy::default(), None);
        assert_eq!(plan.start_ms, 0);
        assert_eq!(plan.reason, StartReason::FromStart);
        assert!(!page.tick(None, 20_000, Some(45 * MINUTE), &ResumePolicy::default(), 1));
        page.flush(None, 20_000, Some(45 * MINUTE), &ResumePolicy::default(), 2)
            .unwrap();
    }

    /// 片尾提示走一遍：到点弹一次，之后不再弹。
    #[test]
    fn the_outro_gate_opens_once_and_the_page_remembers_it() {
        let path = temp_db("outro");
        let mut library = Library::open(&path).unwrap();
        let show = entry("Shows/Dark/S01E02.mkv", Some("Dark"));
        library
            .upsert_source("local", SourceKind::Local, "本地", "/", 1)
            .unwrap();
        library.upsert_media(std::slice::from_ref(&show)).unwrap();
        library
            .set_chapter_mark("dark", ChapterKind::OutroStart, 2_500_000, 1)
            .unwrap();

        let mut page = PlaybackPage::open(Some(&library), Path::new("/m/Shows/Dark/S01E02.mkv"));
        let policy = ResumePolicy::default();
        assert!(!page.tick(Some(&library), 2_400_000, Some(45 * MINUTE), &policy, 1));
        assert!(page.tick(Some(&library), 2_500_000, Some(45 * MINUTE), &policy, 2));
        assert!(!page.tick(Some(&library), 2_700_000, Some(45 * MINUTE), &policy, 3));

        let _ = std::fs::remove_file(&path);
    }

    /// 播放中落盘的水位要跟着走：节流不通过时不写，通过时把水位推到新位置。
    #[test]
    fn the_page_advances_its_persist_watermark_only_when_it_writes() {
        let library = Library::open_in_memory().unwrap();
        let mut page = PlaybackPage::open(Some(&library), Path::new("/x.mkv"));
        let policy = ResumePolicy::default();

        // 片库是空的：认出来的键来自路径，进度从 0 开始。
        assert_eq!(page.session.key.id, MediaId::from_parts("local", "/x.mkv"));
        assert_eq!(page.last_persisted_ms, 0);

        page.tick(Some(&library), 12_000, Some(45 * MINUTE), &policy, 1);
        assert_eq!(page.last_persisted_ms, 12_000);
        assert_eq!(
            watch_state_of(&library, page.session.key.id).position_ms,
            12_000
        );

        page.tick(Some(&library), 15_000, Some(45 * MINUTE), &policy, 2);
        assert_eq!(page.last_persisted_ms, 12_000, "不到 10 秒不写");

        // 库里真有这条条目时，开页就用条目 ID，不另生成一个。
        let show = entry("Shows/Dark/S01E03.mkv", Some("Dark"));
        let mut library = Library::open_in_memory().unwrap();
        library
            .upsert_source("local", SourceKind::Local, "本地", "/", 1)
            .unwrap();
        library.upsert_media(std::slice::from_ref(&show)).unwrap();
        let page = PlaybackPage::open(Some(&library), Path::new("/x/Shows/Dark/S01E03.mkv"));
        assert_eq!(page.session.key.id, show.id);
    }
}
