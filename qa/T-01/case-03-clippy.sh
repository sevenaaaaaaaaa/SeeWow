#!/usr/bin/env bash
# case-03 · 静态检查：cargo clippy --workspace --all-targets -- -D warnings
#
# 证明什么（T-01 DoD 最后一条）：M1 的骨架能把警告当错误通过全量 clippy。
# 怎么判：退出码 0；日志里不出现以 warning:/error: 开头的行。
#   为了不盲等：每 5 秒打印一次日志字节数（增长型标量），450 秒未结束就中断并判失败。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-03-clippy

cd "$RS" || { bad "进不去 $RS"; finish; }
LOG="$ART/clippy.log"
: > "$LOG"
cargo clippy --workspace --all-targets -- -D warnings > "$LOG" 2>&1 &
CARGO_PID=$!
DONE=0
for _ in $(seq 1 90); do
  sleep 5
  BYTES=$(wc -c < "$LOG" | tr -d ' ')
  ALIVE=$(kill -0 "$CARGO_PID" 2>/dev/null && echo yes || echo no)
  printf '  [info] clippy 运行中：log_bytes=%s alive=%s\n' "$BYTES" "$ALIVE"
  if [ "$ALIVE" = "no" ]; then DONE=1; break; fi
done

if [ "$DONE" -eq 0 ]; then
  kill "$CARGO_PID" 2>/dev/null
  bad "clippy 超过 450s 未结束，已中断（见 .artifacts/clippy.log）"
else
  wait "$CARGO_PID"; RC=$?
  if [ $RC -eq 0 ]; then ok "cargo clippy --workspace --all-targets -- -D warnings 退出码 0"; else bad "clippy 退出码 $RC"; fi
  RECHECK=$(grep -c 'Checking seewow' "$LOG")
  info "本次 clippy 重新检查了 $RECHECK 个 crate（0 = cargo 认为产物已是最新，指纹与源码一致）"
  HITS=$(grep -cE '^(warning|error)' "$LOG")
  if [ "${HITS:-0}" -eq 0 ]; then ok "clippy 日志没有 warning/error 行"; else bad "clippy 日志有 $HITS 行 warning/error"; grep -E '^(warning|error)' "$LOG" | head -10; fi
fi
finish
