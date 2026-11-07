//! 让链接器找到 libmpv。
//!
//! Homebrew 把 libmpv 装在 `/opt/homebrew/lib`，它不在 ld64 的默认搜索路径里
//! （实测：`cc t.c -lmpv` → `ld: library 'mpv' not found`），而 `libmpv2-sys` 只发
//! `cargo:rustc-link-lib=mpv`、不发搜索路径。所以这里补一条 search path，
//! 顺序：`SEEWOW_LIBMPV_DIR` → /opt/homebrew/lib → /usr/local/lib → 交给默认路径。
//!
//! 这条 build script 不在任务表 T-01 的文件清单里（清单只列了 `crates/ui/build.rs`），
//! 已在 inbox/Q-01.md 里记为「文件清单外的新增」并给出两条候选与代价。

use std::path::Path;

fn main() {
    println!("cargo:rerun-if-env-changed=SEEWOW_LIBMPV_DIR");

    let mut candidates: Vec<String> = Vec::new();
    if let Ok(dir) = std::env::var("SEEWOW_LIBMPV_DIR") {
        candidates.push(dir);
    }
    candidates.push("/opt/homebrew/lib".to_string());
    candidates.push("/usr/local/lib".to_string());

    for dir in candidates {
        if Path::new(&dir).join("libmpv.dylib").exists() {
            println!("cargo:rustc-link-search=native={dir}");
            return;
        }
    }
    println!(
        "cargo:warning=没找到 libmpv.dylib（试过 SEEWOW_LIBMPV_DIR / /opt/homebrew/lib / /usr/local/lib）"
    );
}
