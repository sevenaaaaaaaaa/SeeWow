#!/usr/bin/env bash
# T-01 的 QA 公共库。所有用例 source 它，用 pass/fail/blocked 输出统一格式。
#
# 退出码约定（run-all.sh 按这个汇总）：
#   0  = 通过
#   1  = 失败（缺陷）
#   77 = blocked（环境限制，不是失败 —— 本机锁屏时的画面类用例）
set -uo pipefail

QA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$QA_DIR/../.." && pwd)"
RS="$REPO/apps/seewow-rs"
APP="$RS/dist/SeeWow.app"
EXE="$APP/Contents/MacOS/SeeWow"
BIN="$RS/target/release/seewow-app"
M1LOG="$HOME/Library/Logs/SeeWow/m1.log"
ART="$QA_DIR/.artifacts"
mkdir -p "$ART"

CASE_ID="${CASE_ID:-case}"
FAILED=0
CHECKS=0

ok()   { CHECKS=$((CHECKS+1)); printf '  [ok]   %s\n' "$*"; }
bad()  { CHECKS=$((CHECKS+1)); FAILED=$((FAILED+1)); printf '  [FAIL] %s\n' "$*"; }
info() { printf '  [info] %s\n' "$*"; }

# 断言：assert_eq 期望 实际 说明
assert_eq() { # expected actual msg
  if [ "$1" = "$2" ]; then ok "$3（=$2）"; else bad "$3：期望 $1，实际 $2"; fi
}
assert_contains() { # haystack needle msg
  case "$1" in *"$2"*) ok "$3";; *) bad "$3：没有找到「$2」";; esac
}
assert_re() { # haystack regex msg
  if printf '%s' "$1" | grep -qE "$2"; then ok "$3"; else bad "$3：没有匹配 /$2/"; fi
}
assert_not_contains() { # haystack needle msg
  case "$1" in *"$2"*) bad "$3：出现了不该有的「$2」";; *) ok "$3";; esac
}

finish() {
  printf '\n%s: checks=%d failed=%d\n' "$CASE_ID" "$CHECKS" "$FAILED"
  [ "$FAILED" -eq 0 ] && exit 0 || exit 1
}

# blocked：屏幕锁定时所有「要看画面」的用例走这里，退出码 77，不算失败
blocked() {
  printf 'BLOCKED: %s\n' "$1"
  printf '  （环境限制：本机 GUI 会话锁屏 CGSSessionScreenIsLocked=1 —— vo=gpu/gpu-next 拿不到 drawable，screencapture 失败；不判失败）\n'
  [ $# -gt 1 ] && printf '  解锁后按 qa/T-01/README.md 的「%s」手工执行并截图\n' "$2"
  exit 77
}

# 屏幕是否锁屏：screencapture 取不到画面即视为锁屏/无显示输出
screen_locked() {
  if screencapture -x "$ART/.probe-screen.png" 2>/dev/null && [ -s "$ART/.probe-screen.png" ]; then
    rm -f "$ART/.probe-screen.png"; return 1
  fi
  return 0
}

# 确保 release 二进制不比源码旧（旧二进制跑出来的结论没有意义）
ensure_release_bin() {
  [ -x "$BIN" ] || { echo "缺 $BIN"; return 1; }
  local newest
  newest=$(find "$RS/crates" -name '*.rs' -newer "$BIN" -print -quit 2>/dev/null)
  if [ -z "$newest" ]; then return 0; fi
  echo "  [info] 源码比二进制新（${newest}），先 cargo build --release -p seewow-app"
  ( cd "$RS" && cargo build --release -p seewow-app > "$ART/release-build.log" 2>&1 ) &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    printf '  [info] 构建中：log_bytes=%s\n' "$(wc -c < "$ART/release-build.log" | tr -d ' ')"
  done
  wait "$pid" || { echo "release 构建失败（见 .artifacts/release-build.log）"; return 1; }
}

# 用 rustc 直接把 QA harness 编到已经构建好的 rlib 上（不往产品目录里加任何文件）
build_harness() { # lib_name src.rs out_bin
  local crate="$1" src="$2" out="$3" rlib pkg
  pkg="${crate//_/-}"
  ( cd "$RS" && cargo build -p "$pkg" -q ) || { echo "cargo build -p $pkg 失败"; return 1; }
  rlib=$(ls -t "$RS"/target/debug/deps/lib"$crate"-*.rlib 2>/dev/null | head -1)
  [ -n "$rlib" ] || { echo "找不到 $crate 的 rlib"; return 1; }
  rustc --edition 2024 "$src" -o "$out" \
    -L dependency="$RS/target/debug/deps" \
    --extern "$crate"="$rlib" \
    -L native=/opt/homebrew/lib
}
