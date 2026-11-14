# SeeWow Rust 重写

Flutter 主线的下一代内核：Rust + Slint 界面，libmpv 自持窗口播视频，macOS 首发。

规划、任务表、验收口径、决策记录全部在 [docs/plan/rust-rewrite-plan.md](../../docs/plan/rust-rewrite-plan.md)。
那份文件是这条线唯一的权威来源；本 README 只讲怎么把它跑起来。

## 前置

- Rust 1.98（rust-toolchain.toml 已固定，rustup 会自动装）。
- macOS 13+。
- libmpv：brew install mpv（M1 的打包脚本会把它复制进 .app；自包含打包属于 M6）。

## 构建与运行

```sh
cargo build -p seewow-app
cargo run -p seewow-app -- /path/to/video.mp4     # 直接播这个文件
SEEWOW_SELFTEST=1 cargo run -p seewow-app -- /path/to/video.mp4   # 脚本化自检
```

日志写在 ~/Library/Logs/SeeWow/m1.log。

不需要窗口也能验证片库链路（M2）：

```sh
seewow-app --scan /path/to/media --json --db /tmp/library.db
seewow-app --scan /path/to/media          # 人读摘要
```

首次运行写库、第二次走增量；`--include-hidden` 收录隐藏目录。

## 测试与检查

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

三条都必须干净；这是 M2 起每个任务的硬门槛。

## 打包

```sh
scripts/make-app-m1.sh
open dist/SeeWow.app
```

产物是 ad-hoc 签名的 SeeWow.app，libmpv 通过 @rpath 进包。

## 当前状态

| 里程碑 | 状态 |
| --- | --- |
| M1 骨架（窗口 / 叠层 / HDR 探针） | 已交付 v2.0.0-m1；验收冻结到 M6 之后 |
| M2 本地片库 / 解析 / SQLite / 收藏搜索 | 完成（自审，2026-11-15）：扫描、解析、SQLite、查询分页、收藏进度、`--scan` 命令行 |

## 目录

| 路径 | 内容 |
| --- | --- |
| crates/core | 领域类型、错误、路径、配置、文件名解析 |
| crates/library | SQLite 片库、扫描、查询、观看状态 |
| crates/sources | SMB / WebDAV / IPTV 片源与列表解析（M4） |
| crates/player | mpv 宿主、窗口定位、HDR 探针 |
| crates/ui | Slint 壳、叠层、输入路由 |
| crates/app | composition root |
