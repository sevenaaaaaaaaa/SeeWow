#!/usr/bin/env bash
# case-13 · 全屏进出与换屏（T-01 DoD 第 7 条）
#
# 证明什么：全屏进/出各一次，画面与界面一起进全屏；把窗口拖到第二块屏（或断开外接屏）
#   不崩溃、界面不跑到屏幕外。
#
# 怎么判：需要真实显示输出。日志层（全屏 toggle 不崩、shutdown 正常）已由 case-06 自动覆盖。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-13-manual-fullscreen

if screen_locked; then
  blocked "要看全屏画面与第二块屏（本机屏幕已锁）" "case-13 · 全屏与换屏"
fi
printf 'MANUAL: 全屏进/出各一次 + 拖到第二块屏，各截一张图。\n'
exit 78
