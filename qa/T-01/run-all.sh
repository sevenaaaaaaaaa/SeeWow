#!/usr/bin/env bash
# T-01 的 QA 总入口：跑 qa/T-01 下的全部用例，逐条报 通过 / 失败 / blocked / 手工待做。
#
# 退出码：0 = 没有失败（blocked 与手工项不算失败）；1 = 至少一条失败。
# 说明：本机 GUI 会话锁屏时，「要看画面」的四条会报 blocked（77），这是环境限制，不是缺陷。
set -uo pipefail
cd "$(dirname "$0")"
QA_DIR="$(pwd)"
export QA_DIR

PASS=0; FAIL=0; BLOCK=0; MANUAL=0
RESULTS=()

for CASE in case-*.sh; do
  [ -x "$CASE" ] || chmod +x "$CASE"
  printf '\n===== %s =====\n' "$CASE"
  bash "$CASE"
  RC=$?
  case $RC in
    0)  PASS=$((PASS+1));   RESULTS+=("通过        $CASE");;
    77) BLOCK=$((BLOCK+1)); RESULTS+=("blocked     $CASE");;
    78) MANUAL=$((MANUAL+1)); RESULTS+=("手工待做    $CASE");;
    *)  FAIL=$((FAIL+1));   RESULTS+=("失败        $CASE");;
  esac
done

printf '\n========== T-01 QA 汇总 ==========\n'
for line in "${RESULTS[@]}"; do printf '%s\n' "$line"; done
printf '\n通过 %d · 失败 %d · blocked %d · 手工待做 %d\n' "$PASS" "$FAIL" "$BLOCK" "$MANUAL"
printf '日志与产物：%s/.artifacts/\n' "$QA_DIR"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
