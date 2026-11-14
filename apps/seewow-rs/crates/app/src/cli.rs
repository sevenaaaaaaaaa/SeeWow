//! 命令行入口：M2 用它验证「扫描 → 建库 → 查询」整条链，不需要 GUI。
//!
//! 用法：
//!   seewow-app --scan DIR [--json] [--include-hidden] [--db PATH]
//!   seewow-app [VIDEO]        打开界面（M1 行为不变）
//!
//! 退出码：0 成功；1 运行失败；2 参数错误。

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;

use seewow_core::{Error, Paths, Result, SourceKind};
use seewow_library::{Library, Query, ScanOptions, SortBy, scan_into_library};

pub const USAGE: &str = "\
用法：
  seewow-app --scan DIR [--json] [--include-hidden] [--db PATH]
  seewow-app [VIDEO]

  --scan DIR         扫描这个目录并写入片库
  --json             以 JSON 输出（只与 --scan 搭配）
  --include-hidden   收录隐藏文件与隐藏目录
  --db PATH          指定片库文件；默认用应用数据目录下的 library.db
  -h, --help         显示这段说明
";

/// 解析后的命令。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    Gui {
        autoplay: Option<PathBuf>,
    },
    Scan {
        root: PathBuf,
        json: bool,
        include_hidden: bool,
        db: Option<PathBuf>,
    },
    Help,
}

/// 纯函数解析，便于单测；不碰文件系统。
pub fn parse_args(args: &[String]) -> std::result::Result<Command, String> {
    let mut scan_root: Option<PathBuf> = None;
    let mut json = false;
    let mut include_hidden = false;
    let mut db: Option<PathBuf> = None;
    let mut help = false;
    let mut positional: Vec<String> = Vec::new();

    let mut index = 1;
    while index < args.len() {
        let arg = args[index].as_str();
        match arg {
            "--scan" => {
                index += 1;
                let value = args.get(index).ok_or("--scan 需要一个目录参数")?;
                if value.starts_with("--") {
                    return Err("--scan 需要一个目录参数".to_string());
                }
                if scan_root.is_some() {
                    return Err("--scan 只能给一次".to_string());
                }
                scan_root = Some(PathBuf::from(value));
            }
            "--json" => json = true,
            "--include-hidden" => include_hidden = true,
            "--db" => {
                index += 1;
                let value = args.get(index).ok_or("--db 需要一个文件路径")?;
                if value.starts_with("--") {
                    return Err("--db 需要一个文件路径".to_string());
                }
                db = Some(PathBuf::from(value));
            }
            "-h" | "--help" => help = true,
            other if other.starts_with("--") => {
                return Err(format!("未知参数 {other}"));
            }
            other => positional.push(other.to_string()),
        }
        index += 1;
    }

    if help {
        return Ok(Command::Help);
    }
    if let Some(root) = scan_root {
        if !positional.is_empty() {
            return Err("扫描模式下不能再给播放文件".to_string());
        }
        return Ok(Command::Scan {
            root,
            json,
            include_hidden,
            db,
        });
    }
    if json || include_hidden || db.is_some() {
        return Err("--json / --include-hidden / --db 只能与 --scan 一起用".to_string());
    }
    if positional.len() > 1 {
        return Err("一次只能打开一个文件".to_string());
    }
    Ok(Command::Gui {
        autoplay: positional.first().map(PathBuf::from),
    })
}

/// 执行扫描命令，返回进程退出码。
pub fn run_scan(root: &Path, json: bool, include_hidden: bool, db: Option<&Path>) -> i32 {
    match scan(root, json, include_hidden, db) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("扫描失败：{error}");
            1
        }
    }
}

fn scan(root: &Path, json: bool, include_hidden: bool, db: Option<&Path>) -> Result<()> {
    if !root.is_dir() {
        return Err(Error::Config(format!(
            "{} 不是可读取的目录",
            root.display()
        )));
    }
    let database = match db {
        Some(path) => path.to_path_buf(),
        None => Paths::discover()?.library_db(),
    };
    let mut library = Library::open(&database)?;

    let source_id = "local";
    let location = root.to_string_lossy().to_string();
    library.upsert_source(
        source_id,
        SourceKind::Local,
        "本机影片",
        &location,
        now_ms(),
    )?;
    let report = scan_into_library(
        &mut library,
        root,
        source_id,
        &ScanOptions { include_hidden },
    )?;
    let total = library.count_media()?;
    let entries = library.search(&Query {
        sort: SortBy::TitleAsc,
        limit: total.max(1),
        ..Query::default()
    })?;

    if json {
        let output = ScanOutput {
            root: location,
            database: database.to_string_lossy().to_string(),
            scanned: report.scanned,
            added: report.added,
            updated: report.updated,
            skipped: report.skipped,
            elapsed_ms: report.elapsed_ms as u64,
            total,
            failures: report
                .failures
                .iter()
                .map(|failure| FailureOutput {
                    path: failure.path.to_string_lossy().to_string(),
                    message: failure.message.clone(),
                })
                .collect(),
            entries: entries.iter().map(EntryOutput::from).collect(),
        };
        let text = serde_json::to_string_pretty(&output)
            .map_err(|error| Error::Internal(format!("输出 JSON 失败：{error}")))?;
        println!("{text}");
    } else {
        println!(
            "扫描 {}：新增 {}、更新 {}、跳过 {}、失败 {}，用时 {} ms；库中共 {} 条",
            root.display(),
            report.added,
            report.updated,
            report.skipped,
            report.failures.len(),
            report.elapsed_ms,
            total
        );
        for failure in &report.failures {
            println!("  失败：{} — {}", failure.path.display(), failure.message);
        }
    }
    Ok(())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ScanOutput {
    root: String,
    database: String,
    scanned: usize,
    added: usize,
    updated: usize,
    skipped: usize,
    elapsed_ms: u64,
    total: usize,
    failures: Vec<FailureOutput>,
    entries: Vec<EntryOutput>,
}

#[derive(Serialize)]
struct FailureOutput {
    path: String,
    message: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EntryOutput {
    id: String,
    path: String,
    title: String,
    show_title: Option<String>,
    kind: String,
    year: Option<i32>,
    season: Option<u32>,
    episode: Option<u32>,
    quality: String,
}

impl From<&seewow_core::MediaEntry> for EntryOutput {
    fn from(entry: &seewow_core::MediaEntry) -> Self {
        Self {
            id: entry.id.to_string(),
            path: entry.relative_path.to_string_lossy().to_string(),
            title: entry.title.clone(),
            show_title: entry.show_title.clone(),
            kind: entry.kind.as_str().to_string(),
            year: entry.year,
            season: entry.season,
            episode: entry.episode,
            quality: entry.quality.clone(),
        }
    }
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        std::iter::once("seewow-app")
            .chain(values.iter().copied())
            .map(str::to_string)
            .collect()
    }

    #[test]
    fn no_arguments_opens_the_gui() {
        assert_eq!(
            parse_args(&args(&[])).unwrap(),
            Command::Gui { autoplay: None }
        );
    }

    #[test]
    fn a_positional_argument_is_the_video_to_play() {
        assert_eq!(
            parse_args(&args(&["/tmp/movie.mkv"])).unwrap(),
            Command::Gui {
                autoplay: Some(PathBuf::from("/tmp/movie.mkv"))
            }
        );
    }

    #[test]
    fn scan_mode_reads_its_flags_in_any_order() {
        let command = parse_args(&args(&[
            "--json",
            "--scan",
            "/media",
            "--db",
            "/tmp/x.db",
            "--include-hidden",
        ]))
        .unwrap();
        assert_eq!(
            command,
            Command::Scan {
                root: PathBuf::from("/media"),
                json: true,
                include_hidden: true,
                db: Some(PathBuf::from("/tmp/x.db")),
            }
        );
    }

    #[test]
    fn help_wins_over_everything() {
        assert_eq!(
            parse_args(&args(&["--scan", "/media", "--help"])).unwrap(),
            Command::Help
        );
    }

    #[test]
    fn missing_values_and_unknown_flags_are_usage_errors() {
        assert!(parse_args(&args(&["--scan"])).is_err());
        assert!(parse_args(&args(&["--db"])).is_err());
        assert!(parse_args(&args(&["--nope"])).is_err());
        assert!(parse_args(&args(&["--scan", "/a", "--json", "movie.mkv"])).is_err());
        assert!(parse_args(&args(&["--json"])).is_err());
    }
}
