#!/usr/bin/env bash
# case-11 · 探针面板：四类数值 + 两个布尔 + 证据来源（T-01 DoD 第 6 条）
#
# 证明什么：本机（SDR 屏）必须显示 pipeline_hdr = true、on_screen_hdr = false、
#   headroom = 1.0（PRD v2 §10 口径：管线已通、未上屏，算通过），并显示证据来源。
#
# 怎么判：GUI 里要能读数（锁屏时拿不到画面），因此：锁屏 → blocked；
#   判定函数本身由 case-04 自动覆盖，日志字段由 case-07 自动覆盖 —— 这里只差「人看到的那一眼」。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-11-manual-hdr-panel

if screen_locked; then
  blocked "要在面板上读 pipeline_hdr / on_screen_hdr / headroom 三个值（本机屏幕已锁）" "case-11 · 探针面板"
fi
printf 'MANUAL: 播 qa/T-01/fixtures/clip-hdr10.mp4，读探针面板数值并截图。\n'
printf '  期望：PIPELINE ✓ / ON SCREEN ✗ / currentEDR 1.000 / evidence_source 2。\n'
exit 78
