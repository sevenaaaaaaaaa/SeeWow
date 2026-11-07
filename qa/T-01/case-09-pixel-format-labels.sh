#!/usr/bin/env bash
# case-09 · Metal 像素格式名字必须与 SDK 定义一致（面板证据的「不谎报」检查）
#
# 证明什么：
#   面板上的 pixfmt 来自 crates/player/src/window.rs 的 metal_pixel_format_name()。
#   ADR-0010 §4 要求「面板必须如实标出证据」—— 名字错了，验收证据就是假的。
#
# 怎么判：以本机 Metal 头文件 MTLPixelFormat.h 的枚举值为真值，
#   逐条比对 window.rs 的 "数值 => 名字"，大小写无关、RGBA/BGRA 顺序必须一致。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-09-pixel-format-labels

export QA_REPO="$REPO"
python3 "$QA_DIR/fixtures/pixel_format_labels.py"
RC=$?
case $RC in
  0) ok "像素格式名字与 SDK 定义一致";;
  2) blocked "拿不到 Metal SDK 头文件，无法比对 MTLPixelFormat 真值" "case-09";;
  *) bad "像素格式名字与 SDK 定义有偏差（见上）";;
esac
finish
