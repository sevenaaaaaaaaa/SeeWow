//! T-08 验收：命令行扫描、JSON 输出与二次增量。

use std::path::{Path, PathBuf};
use std::process::Command;

fn temp_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("seewow-cli-{}-{tag}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn touch(root: &Path, relative: &str) {
    let path = root.join(relative);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, b"x").unwrap();
}

fn run(arguments: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_seewow-app"))
        .args(arguments)
        .output()
        .expect("二进制应能启动")
}

#[test]
fn scan_json_reports_new_entries_then_incremental_updates() {
    let root = temp_dir("scan");
    let db = std::env::temp_dir().join(format!("seewow-cli-{}.db", std::process::id()));
    let _ = std::fs::remove_file(&db);

    touch(&root, "Dune Part Two (2024) 2160p.mkv");
    touch(&root, "Shows/Dark/S01E02.mkv");
    touch(&root, "notes.txt");

    let root_text = root.to_string_lossy().to_string();
    let db_text = db.to_string_lossy().to_string();

    let first = run(&["--scan", &root_text, "--json", "--db", &db_text]);
    assert!(
        first.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&first.stderr)
    );
    let first_json: serde_json::Value = serde_json::from_slice(&first.stdout).unwrap();
    assert_eq!(first_json["scanned"], 2);
    assert_eq!(first_json["added"], 2);
    assert_eq!(first_json["updated"], 0);
    assert_eq!(first_json["total"], 2);
    let entries = first_json["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 2);
    let dune = entries
        .iter()
        .find(|entry| entry["title"] == "Dune Part Two")
        .unwrap();
    assert_eq!(dune["year"], 2024);
    assert_eq!(dune["kind"], "movie");
    let episode = entries
        .iter()
        .find(|entry| entry["path"] == "Shows/Dark/S01E02.mkv")
        .unwrap();
    assert_eq!(episode["showTitle"], "Dark");
    assert_eq!(episode["season"], 1);

    let second = run(&["--scan", &root_text, "--json", "--db", &db_text]);
    assert!(second.status.success());
    let second_json: serde_json::Value = serde_json::from_slice(&second.stdout).unwrap();
    assert_eq!(second_json["added"], 0);
    assert_eq!(second_json["updated"], 2);
    assert_eq!(second_json["total"], 2);

    let human = run(&["--scan", &root_text, "--db", &db_text]);
    assert!(human.status.success());
    let text = String::from_utf8_lossy(&human.stdout);
    assert!(text.contains("新增 0"), "输出：{text}");
    assert!(text.contains("库中共 2 条"), "输出：{text}");

    let _ = std::fs::remove_dir_all(&root);
    let _ = std::fs::remove_file(&db);
}

#[test]
fn usage_errors_exit_two_and_help_exits_zero() {
    let help = run(&["--help"]);
    assert!(help.status.success());
    assert!(String::from_utf8_lossy(&help.stdout).contains("--scan"));

    let bad = run(&["--nope"]);
    assert_eq!(bad.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&bad.stderr).contains("未知参数"));

    let missing = run(&["--scan", "/definitely/not/here"]);
    assert_eq!(missing.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&missing.stderr).contains("扫描失败"));
}
