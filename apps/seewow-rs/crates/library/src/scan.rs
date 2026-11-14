//! 本地目录扫描：递归收视频文件、解析文件名、写入片库。
//!
//! 三条硬规则（M2 DoD）：
//! 1. 只认视频扩展名，其他文件安静跳过；
//! 2. 不跟随符号链接，避免自指目录把扫描拖成死循环；
//! 3. 单个目录读失败记为一条失败记录，整次扫描继续。

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use seewow_core::{MediaEntry, MediaId, MediaKind, Result, parse_file_name};

use crate::Library;

/// 认作视频的扩展名（小写比较）。
pub const VIDEO_EXTENSIONS: &[&str] = &[
    "mkv", "mp4", "m4v", "mov", "avi", "ts", "m2ts", "webm", "flv", "wmv", "mpg", "mpeg", "iso",
];

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ScanOptions {
    pub include_hidden: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScanFailure {
    pub path: PathBuf,
    pub message: String,
}

#[derive(Debug, Default, Clone)]
pub struct ScanReport {
    /// 走进库的条目数（已通过扩展名与隐藏过滤）。
    pub scanned: usize,
    /// 本次新增。
    pub added: usize,
    /// 本次更新（文件已在库里）。
    pub updated: usize,
    /// 被扩展名、隐藏规则、符号链接跳过的文件数。
    pub skipped: usize,
    pub failures: Vec<ScanFailure>,
    pub elapsed_ms: u128,
}

/// 递归收集一个目录下的视频条目。不写库，方便单测与「先看再导」。
pub fn collect_media(
    root: &Path,
    source_id: &str,
    options: &ScanOptions,
) -> (Vec<MediaEntry>, ScanReport) {
    let started = Instant::now();
    let mut entries = Vec::new();
    let mut report = ScanReport::default();
    let mut seen_paths = HashSet::new();
    let mut stack = vec![root.to_path_buf()];

    while let Some(dir) = stack.pop() {
        let read = match std::fs::read_dir(&dir) {
            Ok(read) => read,
            Err(error) => {
                report.failures.push(ScanFailure {
                    path: dir.clone(),
                    message: error.to_string(),
                });
                continue;
            }
        };
        let mut children: Vec<PathBuf> = Vec::new();
        for entry in read {
            let entry = match entry {
                Ok(entry) => entry,
                Err(error) => {
                    report.failures.push(ScanFailure {
                        path: dir.clone(),
                        message: error.to_string(),
                    });
                    continue;
                }
            };
            let path = entry.path();
            let file_type = match entry.file_type() {
                Ok(file_type) => file_type,
                Err(error) => {
                    report.failures.push(ScanFailure {
                        path: path.clone(),
                        message: error.to_string(),
                    });
                    continue;
                }
            };
            if file_type.is_symlink() {
                report.skipped += 1;
                continue;
            }
            if !options.include_hidden && is_hidden(&path) {
                report.skipped += 1;
                continue;
            }
            if file_type.is_dir() {
                children.push(path);
            } else if file_type.is_file() {
                if !is_video(&path) {
                    report.skipped += 1;
                    continue;
                }
                if let Some(entry) = media_entry(root, source_id, &path, &mut seen_paths) {
                    entries.push(entry);
                    report.scanned += 1;
                }
            }
        }
        // read_dir 顺序随文件系统变化；排序让同一目录的扫描结果稳定。
        children.sort();
        stack.extend(children.into_iter().rev());
    }

    entries.sort_by(|a, b| a.relative_path.cmp(&b.relative_path));
    report.elapsed_ms = started.elapsed().as_millis();
    (entries, report)
}

/// 扫描并写入片库；返回的报告区分新增与更新。
pub fn scan_into_library(
    library: &mut Library,
    root: &Path,
    source_id: &str,
    options: &ScanOptions,
) -> Result<ScanReport> {
    let (entries, mut report) = collect_media(root, source_id, options);
    let existing = library.existing_ids(source_id)?;
    report.added = entries
        .iter()
        .filter(|entry| !existing.contains(&entry.id))
        .count();
    report.updated = entries.len() - report.added;
    library.upsert_media(&entries)?;
    Ok(report)
}

fn media_entry(
    root: &Path,
    source_id: &str,
    path: &Path,
    seen: &mut HashSet<PathBuf>,
) -> Option<MediaEntry> {
    let relative = path.strip_prefix(root).ok()?.to_path_buf();
    if !seen.insert(relative.clone()) {
        return None;
    }
    let relative_text = relative.to_string_lossy().to_string();
    let file_name = path.file_name()?.to_string_lossy().to_string();
    let parent_folder = path
        .parent()
        .and_then(|parent| parent.file_name())
        .map(|name| name.to_string_lossy().to_string());
    let parsed = parse_file_name(&file_name, parent_folder.as_deref());
    let kind = if parsed.season.is_some() && parsed.episode.is_some() {
        MediaKind::Episode
    } else {
        MediaKind::Movie
    };
    Some(MediaEntry {
        id: MediaId::from_parts(source_id, &relative_text),
        source_id: source_id.to_string(),
        relative_path: relative,
        kind,
        title: parsed.title,
        show_title: parsed.show_title,
        year: parsed.year,
        season: parsed.season,
        episode: parsed.episode,
        quality: parsed.quality,
        added_at_ms: now_ms(),
    })
}

fn is_hidden(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with('.'))
}

fn is_video(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase)
        .is_some_and(|extension| VIDEO_EXTENSIONS.contains(&extension.as_str()))
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}
