#!/usr/bin/env bash
# case-04 · HDR 判定的口径（ADR-0010 v3 + PRD v2 §10 + T-01 DoD）
#
# 证明什么：
#   T-01 的 DoD 要求本机（SDR 屏）显示 pipeline_hdr = true、on_screen_hdr = false、
#   headroom = 1.00，并且显示证据来源。这条只能靠「判定函数真的按 ADR 算」来保证，
#   不能靠肉眼看截图。所以这个用例直接调用 seewow_player::probe::judge，
#   把 ADR-0010 §1/§2/§4 的每条结论当成断言。
#
# 怎么判：编译 fixtures/probe_adr_harness.rs（rustc 直接链已构建的 rlib，不动产品目录），
#   运行它；任何一条断言不成立即整条用例失败。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-04-probe-adr

OUT="$ART/probe-adr-harness"
if ! build_harness seewow_player "$QA_DIR/fixtures/probe_adr_harness.rs" "$OUT"; then
  bad "harness 编译失败（见上面的 rustc 输出）"
  finish
fi
"$OUT"
RC=$?
if [ $RC -eq 0 ]; then ok "ADR-0010 v3 的判定口径全部成立"; else bad "判定口径有断言不成立（见上）"; fi
finish
