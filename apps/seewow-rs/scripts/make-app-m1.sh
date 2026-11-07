#!/usr/bin/env bash
# M1 打包：产出可双击的 SeeWow.app（ad-hoc 签名，与现有发布方式一致）。
#
# 用法：
#   scripts/make-app-m1.sh            # 出包
#   open dist/SeeWow.app              # 双击启动
#   open -a dist/SeeWow.app --args /path/to/video.mp4   # 顺带自动播放
#
# 包内自带 libmpv.2.dylib（改依赖到 @rpath）；libmpv 自己的依赖（ffmpeg 等）
# 仍来自 Homebrew —— 完整的自包含打包是 T-34 的事，M1 只保证「本机能双击跑」。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_NAME="seewow-app"
APP_NAME="SeeWow"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
EXE="$APP/Contents/MacOS/$APP_NAME"

cd "$ROOT"

echo "==> cargo build --release -p $BIN_NAME"
cargo build --release -p "$BIN_NAME"

echo "==> 清理旧包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

echo "==> 可执行文件"
cp "$ROOT/target/release/$BIN_NAME" "$EXE"

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SeeWow</string>
  <key>CFBundleDisplayName</key><string>SeeWow</string>
  <key>CFBundleExecutable</key><string>SeeWow</string>
  <key>CFBundleIdentifier</key><string>com.seewow.seewow.rs</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# ---- libmpv：拷进包内，把可执行文件的依赖改到 @rpath ----
LIBMPV_CANDIDATES=("${SEEWOW_LIBMPV_DIR:-}/libmpv.2.dylib" "/opt/homebrew/lib/libmpv.2.dylib" "/usr/local/lib/libmpv.2.dylib")
LIBMPV=""
for candidate in "${LIBMPV_CANDIDATES[@]}"; do
  if [ -f "$candidate" ]; then LIBMPV="$candidate"; break; fi
done

if [ -n "$LIBMPV" ]; then
  echo "==> libmpv: $LIBMPV"
  cp -L "$LIBMPV" "$APP/Contents/Frameworks/libmpv.2.dylib"
  ORIGINAL_ID="$(otool -D "$APP/Contents/Frameworks/libmpv.2.dylib" | tail -n 1)"
  echo "    original install_name: $ORIGINAL_ID"
  install_name_tool -id "@rpath/libmpv.2.dylib" "$APP/Contents/Frameworks/libmpv.2.dylib"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE" 2>/dev/null || true
  install_name_tool -change "$ORIGINAL_ID" "@rpath/libmpv.2.dylib" "$EXE"
else
  echo "WARN: 没找到 libmpv.2.dylib（会依赖系统里的 /opt/homebrew/lib）" >&2
fi

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP"

echo "==> 校验"
codesign --verify --verbose=2 "$APP" || true
echo
echo "app: $APP"
echo "启动: open \"$APP\"    （自动播放: open -a \"$APP\" --args /path/to/video.mp4）"
echo "日志: ~/Library/Logs/SeeWow/m1.log"
