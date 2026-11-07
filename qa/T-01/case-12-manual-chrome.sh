#!/usr/bin/env bash
# case-12 · 页头 / 红绿灯 / 控制条的观感（T-01 DoD 第 3、4、5 条）
#
# 证明什么：红绿灯默认看不见、进左上热区才淡入；播放中静止 3 秒页头与红绿灯 220ms 淡出，
#   动指针 / Esc / 暂停 / 指针到顶部 8px 淡入；底部控制条出现、点一下真的暂停、3 秒自动隐藏。
#
# 怎么判：动画与手感只能人看。纯判定函数（谁该显示、3 秒阈值、热区尺寸）已由 case-05 自动覆盖，
#   这里只覆盖「看得见的过渡与点击」。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-12-manual-chrome

if screen_locked; then
  blocked "要看动画与点击反馈：页头淡出 220ms / 红绿灯热区 / 控制条暂停（本机屏幕已锁）" "case-12 · 页头与控制条"
fi
printf 'MANUAL: 按 README 的清单走一遍，每步截一张图。\n'
exit 78
