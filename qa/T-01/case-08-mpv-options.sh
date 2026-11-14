#!/usr/bin/env bash
# case-08 · mpv 启动选项的回归护栏（Q-02 的实测结论）
#
# 证明什么：
#   M1 的 mpv 选项是 THL/Q-02 用证据换来的：force-window=yes 会让「先建窗、后 loadfile」
#   永远不生效（VO 卡在 swapBuffer），所以它必须不在选项表里；10-bit XR 上下文必须开；
#   窗口标题必须等于定位窗口用的键；osc/键盘绑定必须关（壳自己画、键盘单一主人）。
#
# 怎么判：直接读 crates/player/src/host.rs 的 MPV_OPTIONS 与 HOST_WINDOW_TITLE（静态检查，不需要跑起来）。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-08-mpv-options

HOST="$RS/crates/player/src/host.rs"
[ -f "$HOST" ] || { bad "缺 $HOST"; finish; }
SRC=$(cat "$HOST")

assert_not_contains "$SRC" '("force-window"' "选项表里没有 force-window（Q-02：会让 loadfile 永不生效）"
assert_contains "$SRC" '("cocoa-cb-10bit-context", "yes")' "开了 10-bit XR 上下文（HDR 管线的前提）"
assert_contains "$SRC" '("cocoa-cb-output-csp", "auto")' "输出色彩空间默认 auto，探到 PQ 再切"
assert_contains "$SRC" '("vo", "gpu-next")' "vo = gpu-next"
assert_contains "$SRC" '("osc", "no")' "osc 关掉（壳自己画控制条）"
assert_contains "$SRC" '("input-vo-keyboard", "no")' "mpv 不收键盘（键盘单一主人）"
assert_contains "$SRC" '("keep-open", "yes")' "keep-open（播完停在最后一帧）"
assert_contains "$SRC" 'pub const HOST_WINDOW_TITLE: &str = "SeeWow Player";' "宿主窗口标题 = 定位窗口用的键"
assert_contains "$SRC" '("title", HOST_WINDOW_TITLE)' "选项里把 title 设成同一个键"

# 日志路径必须就是 DoD 写的那条
assert_contains "$SRC" '.join("Library")' "日志落在 ~/Library/Logs/SeeWow/"
assert_contains "$SRC" '"m1.log"' "日志文件名是 m1.log"

finish
