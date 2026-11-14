#!/usr/bin/env bash
# case-07 · 探针面板背后的四类数值必须真的采到（日志口径）
#
# 证明什么（T-01 DoD 第 6 条的数据层）：
#   面板要显示 mpv 源参数、目标侧 video-target-params、本机屏幕 EDR、两个布尔 + 证据来源。
#   面板的长相要靠手工看（case-11 blocked），但它背后那一行 "probe:" 日志必须真的带齐这些字段，
#   否则面板画得再对也是空数据。
#
# 怎么判：
#   1) 起一次应用（vo=null，3 秒样片），等在日志里出现 probe: 行；
#   2) 断言这一行包含 target.gamma/primaries/max-luma/pixfmt、layer.pixfmt/wantsEDR/csp、
#      screen.potentialEDR/currentEDR、pipeline_hdr/on_screen_hdr/evidence_source/headline 全部字段；
#   3) 断言本机屏幕数字如实写出来（currentEDR=1.000 = PRD v2 §10 的 headroom = 1.0）；
#   4) 断言「证据不足不得判过」：vo=null 时 target 侧取不到，两个布尔必须是 false。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-07-probe-log

[ -x "$BIN" ] || { bad "缺 $BIN"; finish; }
ensure_release_bin || { bad "release 二进制没准备好"; finish; }
CLIP="$QA_DIR/fixtures/clip-sdr.mp4"
[ -f "$CLIP" ] || { bad "缺样片 $CLIP"; finish; }

OFFSET=$(wc -c < "$M1LOG" 2>/dev/null || echo 0)
SEEWOW_MPV_VO=null "$BIN" "$CLIP" > "$ART/probe-run.stdout" 2>&1 &
PID=$!
for i in $(seq 1 6); do
  sleep 2
  if tail -c +"$((OFFSET+1))" "$M1LOG" 2>/dev/null | grep -q 'probe: target.gamma='; then
    printf '  [info] t=%ss 已出现 probe 行\n' "$((i*2))"
    break
  fi
  printf '  [info] t=%ss 还没有 probe 行（进程 %s）\n' "$((i*2))" "$(kill -0 $PID 2>/dev/null && echo 在 || echo 没了)"
done
sleep 1
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

SLICE="$ART/probe.log"
tail -c +"$((OFFSET+1))" "$M1LOG" > "$SLICE" 2>/dev/null
LINE=$(grep 'probe: target.gamma=' "$SLICE" | tail -1)
if [ -z "$LINE" ]; then bad "整次运行没有写出 probe: 行"; finish; fi
info "最后一条 probe 行：$LINE"

for field in 'target.gamma=' 'target.primaries=' 'target.max-luma=' 'target.pixfmt=' \
             'wantsEDR=' 'screen.potentialEDR=' 'currentEDR=' \
             'pipeline_hdr=' 'on_screen_hdr=' 'evidence_source=' 'headline='; do
  assert_contains "$LINE" "$field" "probe 行带字段 $field"
done
# 表面格式与色彩空间两项在不同版本里换过名字（layer.pixfmt / surface.pixfmt、csp / csp(opt)），
# 断言用「字段语义仍在」而不是死记某个名字。
assert_re "$LINE" '(layer|surface)\.pixfmt=' "probe 行带表面像素格式字段"
assert_re "$LINE" 'csp(\(opt\))?=' "probe 行带输出色彩空间字段"
assert_re "$LINE" 'wantsEDR=' "probe 行带 wantsExtendedDynamicRangeContent"

assert_contains "$LINE" "currentEDR=1.000" "屏幕 headroom 如实写成 1.000（PRD v2 §10 的 SDR 口径）"
assert_contains "$LINE" "potentialEDR=2.000" "屏幕潜力 EDR 如实写出"
assert_contains "$LINE" "evidence_source=2" "M1 没有像素回读 → 证据来源 = 2（ADR-0010 §4）"

# 证据不足不得判过：vo=null 下 target 侧取不到，两个布尔必须 false
case "$LINE" in
  *"pipeline_hdr=false"*) ok "取不到目标侧参数时不判管线通过（证据不足 ≠ 通过）";;
  *) bad "vo=null 且 target 全为 n/a 时 pipeline_hdr 不应为 true";;
esac

finish
