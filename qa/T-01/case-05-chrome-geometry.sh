#!/usr/bin/env bash
# case-05 · 壳层几何与自动隐藏规则（不看画面也能判的那部分）
#
# 证明什么（T-01 DoD 第 3/4/5 条 + CRD-0003 §3/§4）：
#   红绿灯只认左上 80×32 热区；页头「窗口化常显 / 暂停常显 / 播放中全屏静止 3 秒隐藏 /
#   指针到顶部 8px 唤出」；控制条 3 秒无操作收起；淡入淡出 220ms。
#
# 怎么判：
#   1) 从 crates/ui/ui/skeleton.slint 读出真实几何（traffic-w / traffic-h / top-edge / header-h …）；
#   2) 把几何喂给 fixtures/chrome_harness.rs，对 hit::traffic_visible / header_visible /
#      controls_visible / region_at / IDLE_HIDE 逐条断言；
#   3) 断言 skeleton.slint 里两处 opacity 动画是 220ms（DoD 的「淡出 220ms」）。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-05-chrome-geometry

SLINT="$RS/crates/ui/ui/skeleton.slint"
[ -f "$SLINT" ] || { bad "缺 $SLINT"; finish; }

num() { # 属性名 → 数字
  sed -nE "s/.*out property <length> $1: ([0-9.]+)px;.*/\1/p" "$SLINT" | head -1
}

W=$(num width);           [ -n "$W" ] || W=1200
H=$(num height);          [ -n "$H" ] || H=760
HEADER_H=$(num header-h)
GUTTER=$(num gutter)
CONTROLS_H=$(num controls-h)
TRAFFIC_W=$(num traffic-w)
TRAFFIC_H=$(num traffic-h)
PROBE_W=$(num probe-w)
PROBE_H=$(num probe-h)
TOP_EDGE=$(num top-edge)
ACTIONS_W=$(num header-actions-w)
info "skeleton.slint: header-h=$HEADER_H traffic=$TRAFFIC_W x $TRAFFIC_H top-edge=$TOP_EDGE controls-h=$CONTROLS_H"

FADES=$(grep -c 'animate opacity { duration: 220ms' "$SLINT")
assert_eq 2 "$FADES" "页头与红绿灯的淡入淡出都是 220ms（两处动画）"

OUT="$ART/chrome-harness"
if ! build_harness seewow_ui "$QA_DIR/fixtures/chrome_harness.rs" "$OUT"; then
  bad "harness 编译失败"
  finish
fi
"$OUT" "$W" "$H" "$HEADER_H" "$GUTTER" "$CONTROLS_H" "$TRAFFIC_W" "$TRAFFIC_H" "$PROBE_W" "$PROBE_H" "$TOP_EDGE" "$ACTIONS_W"
RC=$?
if [ $RC -eq 0 ]; then ok "壳层几何与自动隐藏规则全部成立"; else bad "壳层几何/自动隐藏有断言不成立（见上）"; fi
finish
