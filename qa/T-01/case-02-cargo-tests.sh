#!/usr/bin/env bash
# case-02 · 任务表 §0.5 与 T-01 DoD 指定的测试命令
#
# 证明什么：
#   DoD 命令 cargo test -p seewow-player --test probe_verdict 与
#   cargo test --workspace 在当前树上真的绿 —— 不是「跑过」，是「这次跑的」。
#
# 怎么判：两条命令退出码都是 0，并且 probe_verdict 的通过条数 > 0（防止空跑）。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-02-cargo-tests

cd "$RS" || { bad "进不去 $RS"; finish; }

cargo test -p seewow-player --test probe_verdict > "$ART/probe-verdict.log" 2>&1
RC=$?
if [ $RC -eq 0 ]; then ok "cargo test -p seewow-player --test probe_verdict 退出码 0"; else bad "cargo test --test probe_verdict 退出码 $RC（见 .artifacts/probe-verdict.log）"; fi
PASSED=$(grep -oE 'test result: ok\. [0-9]+ passed' "$ART/probe-verdict.log" | grep -oE '[0-9]+' | head -1)
if [ -n "${PASSED:-}" ] && [ "${PASSED:-0}" -gt 0 ]; then ok "probe_verdict 实际通过 $PASSED 条"; else bad "probe_verdict 没有跑出任何通过用例（空跑）"; fi

cargo test --workspace > "$ART/workspace-test.log" 2>&1
RC=$?
if [ $RC -eq 0 ]; then ok "cargo test --workspace 退出码 0"; else bad "cargo test --workspace 退出码 $RC（见 .artifacts/workspace-test.log）"; fi
TOTALS=$(grep -cE '^test result: ok\.' "$ART/workspace-test.log")
if [ "${TOTALS:-0}" -gt 0 ]; then ok "workspace 里 $TOTALS 个测试目标全绿"; else bad "workspace 没有任何测试目标跑绿"; fi
grep -E '^test result: FAILED|panicked' "$ART/workspace-test.log" | head -5

finish
