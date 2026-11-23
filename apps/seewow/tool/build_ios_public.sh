#!/bin/bash
# 公开分发的 iOS 包：不随包带任何内置播放源（和 build_macos_public.sh 同一套机制）。
#
#   1. 把 assets/sources/builtin_sources.json 与 lib/domain/builtin_seeds.g.dart
#      暂时挪走，种子换成空表；
#   2. --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true；
#   3. 产物校验：包里不得有源包文件，App 二进制里不得出现内置站点域名；
#   4. 无条件恢复（trap）。
#
# 用法：
#   apps/seewow/tool/build_ios_public.sh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$project_root/../.." && pwd)"
cd "$project_root"

pack="assets/sources/builtin_sources.json"
seeds="lib/domain/builtin_seeds.g.dart"
stash="$(mktemp -d "${TMPDIR:-/tmp}/seewow-ios-public.XXXXXX")"
restore() {
  [[ -f "$stash/builtin_sources.json" ]] && mv "$stash/builtin_sources.json" "$pack"
  [[ -f "$stash/builtin_seeds.g.dart" ]] && mv "$stash/builtin_seeds.g.dart" "$seeds"
  rm -rf "$stash"
}
trap restore EXIT INT TERM

version="$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)"
local_build="$(sed -n 's/^version: [0-9][0-9.]*+\([0-9]*\).*/\1/p' pubspec.yaml)"
public_build=$((local_build + 1))
stamp="public-$(git -C "$repo_root" rev-parse --short HEAD) $(date +%Y-%m-%dT%H:%M)"

echo "iOS 公开包：$version ($public_build)，不带内置源"
mv "$pack" "$stash/builtin_sources.json"
mv "$seeds" "$stash/builtin_seeds.g.dart"
cat > "$seeds" <<'DART'
// 公开包构建期间的占位：本版不随包带任何内置站点。
import 'online_source.dart';

const builtinPackSites = <OnlineSite>[];
DART

flutter build ios --release --no-codesign \
  --build-number "$public_build" \
  --dart-define=SEEWOW_VERSION="$version" \
  --dart-define="SEEWOW_BUILD_STAMP=$stamp" \
  --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true \
  "$@"

app="$project_root/build/ios/iphoneos/Runner.app"
platform="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$app/Info.plist")"
[[ "$platform" == "iPhoneOS" ]] || { echo "不是真机构建（$platform），不打包" >&2; exit 1; }
if find "$app" -name 'builtin_sources.json' | grep -q .; then
  echo '公开包里仍能找到 builtin_sources.json，拒绝打包' >&2
  exit 1
fi
app_bin="$app/Frameworks/App.framework/App"
if grep -aq 'zuidapi\.com' "$app_bin"; then
  echo '公开包的二进制里仍能找到内置站点地址，拒绝打包' >&2
  exit 1
fi
built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")"
built_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"
echo "产物版本：$built_version ($built_number)"

staging="$(mktemp -d "${TMPDIR:-/tmp}/seewow-ios-public-ipa.XXXXXX")"
trap 'restore; rm -rf "$staging"' EXIT INT TERM
mkdir -p "$staging/Payload"
ditto --norsrc "$app" "$staging/Payload/SeeWow.app"

out="$repo_root/dist/SeeWow-iOS-$version-public-nosources.ipa"
rm -f "$out" "$out.sha256"
ditto -c -k --norsrc --keepParent "$staging/Payload" "$out"
unzip -tq "$out"
shasum -a 256 "$out" > "$out.sha256"
echo "$out"
