#!/usr/bin/env bash
# case-01 · 可双击的 SeeWow.app 包结构 + ad-hoc 签名
#
# 证明什么（T-01 DoD 第 1 条 / 第 7 条的一部分）：
#   scripts/make-app-m1.sh 产出的 dist/SeeWow.app 是一个自洽的 macOS App 包：
#   Info.plist 完整、可执行文件在、libmpv 打进包内并把依赖改成 @rpath、
#   ad-hoc 签名校验通过 —— 也就是「负责人不装 Rust 也能双击跑」的物质前提。
#
# 怎么判：
#   1) 脚本存在且被标记可执行，且里面确实调用了 codesign 与 install_name_tool；
#   2) 包内四个必需路径都在；
#   3) codesign --verify --deep --strict 退出码 = 0；
#   4) otool -L 里 libmpv 走 @rpath，不再指向 /opt/homebrew（换机器/换目录会断）；
#   5) Info.plist 的 CFBundleExecutable 与真实可执行文件同名。
#   重打包：SEEWOW_QA_REBUILD=1 时会先跑一遍 scripts/make-app-m1.sh（约 1 分钟）。
set -uo pipefail
source "$(dirname "$0")/lib.sh"
CASE_ID=case-01-bundle

if [ "${SEEWOW_QA_REBUILD:-0}" = "1" ]; then
  info "SEEWOW_QA_REBUILD=1 → 重新打包（scripts/make-app-m1.sh）"
  bash "$RS/scripts/make-app-m1.sh" > "$ART/make-app.log" 2>&1 || bad "make-app-m1.sh 退出码非 0（见 .artifacts/make-app.log）"
fi

[ -f "$RS/scripts/make-app-m1.sh" ] && ok "scripts/make-app-m1.sh 存在" || bad "缺 scripts/make-app-m1.sh"
[ -x "$RS/scripts/make-app-m1.sh" ] && ok "打包脚本可执行" || bad "打包脚本没有可执行位"
assert_contains "$(cat "$RS/scripts/make-app-m1.sh")" "codesign --force --deep --sign -" "脚本做 ad-hoc 签名"
assert_contains "$(cat "$RS/scripts/make-app-m1.sh")" "install_name_tool -change" "脚本把 libmpv 依赖改到 @rpath"

[ -d "$APP" ] && ok "dist/SeeWow.app 存在" || { bad "没有 dist/SeeWow.app（先跑 scripts/make-app-m1.sh）"; finish; }
[ -x "$EXE" ] && ok "包内可执行文件存在且可执行" || bad "缺 Contents/MacOS/SeeWow"
[ -f "$APP/Contents/Info.plist" ] && ok "Info.plist 存在" || bad "缺 Info.plist"
[ -f "$APP/Contents/Frameworks/libmpv.2.dylib" ] && ok "libmpv.2.dylib 打进包内" || bad "包内没有 libmpv.2.dylib"

BUNDLE_EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null)
assert_eq "SeeWow" "${BUNDLE_EXE:-}" "Info.plist 的 CFBundleExecutable"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)
assert_eq "com.seewow.seewow.rs" "${BUNDLE_ID:-}" "Info.plist 的 CFBundleIdentifier"

codesign --verify --deep --strict "$APP" > "$ART/codesign.log" 2>&1
assert_eq 0 "$?" "codesign --verify --deep --strict 通过"

LINKS=$(otool -L "$EXE" 2>/dev/null)
assert_contains "$LINKS" "@rpath/libmpv.2.dylib" "可执行文件的 libmpv 走 @rpath"
assert_not_contains "$LINKS" "/opt/homebrew/lib/libmpv" "可执行文件不再硬链 Homebrew 路径"

finish
