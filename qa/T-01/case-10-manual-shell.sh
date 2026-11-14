#!/usr/bin/env bash
# case-10 · 壳窗口：没有系统标题栏、没有白底闪屏、画面区真的在播（T-01 DoD 第 1、2 条）
#
# 证明什么：窗口顶部没有「只有标题 + 三个按钮」的横条，内容延伸到顶部；
#   页头由界面自己画；启动时没有白底闪一下；画面区能正常播放本地视频。
#
# 怎么判：必须人眼看 + 截图（本机锁屏时 vo 拿不到 drawable，screencapture 也失败）。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-10-manual-shell

if screen_locked; then
  blocked "要看画面：无系统标题栏 / 无白底闪屏 / 画面区播放（本机屏幕已锁）" "case-10 · 壳窗口"
fi
printf 'MANUAL: 屏幕没锁，但这条要人眼看 + 截图。\n'
printf '  步骤见 qa/T-01/README.md「case-10 · 壳窗口」，截图存到 qa/T-01/evidence/。\n'
exit 78
