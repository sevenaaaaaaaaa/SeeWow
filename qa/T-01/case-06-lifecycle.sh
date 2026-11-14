#!/usr/bin/env bash
# case-06 · 无显示器也能跑的那条生命周期：启动 → 播放 → 全屏进 → 全屏出 → 关闭 → 进程消失
#
# 证明什么（T-01 DoD 第 1 / 7 / 8 条的能量化部分）：
#   - 进程真的能启动、能加载文件、能播放到结束；
#   - 全屏进出各一次不崩（本机锁屏时用 SEEWOW_MPV_VO=null 关掉 VO，窗口路径仍会走）；
#   - 关闭后进程真的消失，日志里能看到这次播放的开始与结束；
#   - 壳窗口是「无系统标题栏 + 透明」的那一个（styleMask=0xc、opaque=false）。
#
# 怎么判：SEEWOW_SELFTEST=1 让应用自己走 全屏进(2.5s) → 全屏出(7s) → 关闭(11s)；
#   用例只允许它 45 秒内退出，然后按日志切片逐条断言。断言不成立即失败。
#   画面到底有没有真的出现 —— 那是 case-11/13 的手工项（锁屏 blocked）。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-06-lifecycle

[ -x "$BIN" ] || { bad "缺 $BIN（先 cargo build --release -p seewow-app 或跑 scripts/make-app-m1.sh）"; finish; }
CLIP="$QA_DIR/fixtures/clip-lifecycle.mp4"
[ -f "$CLIP" ] || { bad "缺样片 $CLIP（跑 fixtures/gen-fixtures.sh）"; finish; }

OFFSET=$(wc -c < "$M1LOG" 2>/dev/null || echo 0)
SEEWOW_MPV_VO=null SEEWOW_SELFTEST=1 "$BIN" "$CLIP" > "$ART/lifecycle.stdout" 2>&1 &
PID=$!
echo "$PID" > "$ART/lifecycle.pid"
info "启动 pid=$PID log_offset=$OFFSET"

EXITED=0
for i in $(seq 1 22); do
  sleep 2
  if ! kill -0 "$PID" 2>/dev/null; then EXITED=1; break; fi
  NOW=$(wc -c < "$M1LOG" 2>/dev/null || echo 0)
  printf '  [info] t=%ss 进程在，日志字节=%s（增量 %s）\n' "$((i*2))" "$NOW" "$((NOW-OFFSET))"
done

if [ "$EXITED" -eq 0 ]; then
  kill "$PID" 2>/dev/null
  bad "45 秒内没有退出（SELFTEST 的关闭步骤没走完）"
else
  wait "$PID"; RC=$?
  assert_eq 0 "$RC" "进程退出码"
  kill -0 "$PID" 2>/dev/null && bad "进程还在（活动监视器里会残留）" || ok "进程真的消失（kill -0 失败）"
fi

SLICE="$ART/lifecycle.log"
tail -c +"$((OFFSET+1))" "$M1LOG" > "$SLICE" 2>/dev/null
info "本次运行的日志切片 ${SLICE}（$(wc -l < "$SLICE" | tr -d ' ') 行）"

S=$(cat "$SLICE")
assert_contains "$S" "app: start version=" "日志里有这次启动"
assert_contains "$S" "selftest=true" "这次跑的是脚本化自检"
assert_contains "$S" "mpv init: 完成 mpv-version=" "libmpv 真的初始化了"
assert_contains "$S" "playback: 请求 loadfile path=clip-lifecycle.mp4" "日志里有播放开始（请求 loadfile）"
assert_contains "$S" "playback: begin" "日志里有 playback: begin"
assert_contains "$S" "SELFTEST: step 1 全屏进入" "全屏进入发生过"
assert_contains "$S" "SELFTEST: step 2 全屏退出" "全屏退出发生过"
assert_contains "$S" "SELFTEST: step 3 关闭" "关闭步骤执行过"
assert_contains "$S" "playback: end reason=quit" "日志里有这次播放的结束"
assert_contains "$S" "app: shutdown done" "app: shutdown done（叠层先撤，再让 mpv 退出）"
assert_contains "$S" "app: exit" "app: exit"
assert_not_contains "$S" "panic:" "日志里没有 panic"

# 壳窗口的证据：没有系统标题栏（styleMask 不含 NSWindowStyleMaskTitled=1），且透明
assert_contains "$S" "styleMask=0xc" "壳窗口 styleMask=0xc（无 Titled 位 → 没有系统标题栏）"
assert_contains "$S" "opaque=false" "壳窗口是透明窗口（不会白底闪屏的物质前提）"

finish
