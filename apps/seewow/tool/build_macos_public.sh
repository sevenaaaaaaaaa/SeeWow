#!/bin/bash
# 公开分发包（上 GitHub 那一份）：不随包带任何内置播放源。
#
# 本地预览包、iOS IPA、iCloud 那份都带源；只有这个脚本出的包不带：
#   1. 把 assets/sources/builtin_sources.json 暂时挪走（目录里留 README.txt 占位）；
#   2. 用 --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true 构建，代码种子也不生效；
#   3. 校验产物里确实没有源包文件，有就直接失败，不打包；
#   4. 无条件恢复源包（trap，构建失败也不会把仓库留在半截状态）。
#
# 用法：
#   apps/seewow/tool/build_macos_public.sh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$project_root/../.." && pwd)"
cd "$project_root"

pack="assets/sources/builtin_sources.json"
seeds="lib/domain/builtin_seeds.g.dart"
stash="$(mktemp -d "${TMPDIR:-/tmp}/seewow-public.XXXXXX")"
restore() {
  [[ -f "$stash/builtin_sources.json" ]] && mv "$stash/builtin_sources.json" "$pack"
  [[ -f "$stash/builtin_seeds.g.dart" ]] && mv "$stash/builtin_seeds.g.dart" "$seeds"
  rm -rf "$stash"
}
trap restore EXIT INT TERM

if [[ ! -f "$pack" ]]; then
  echo "找不到 $pack，先确认工作区是干净的" >&2
  exit 1
fi

version="$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)"
local_build="$(sed -n 's/^version: [0-9][0-9.]*+\([0-9]*\).*/\1/p' pubspec.yaml)"
if [[ -z "$version" || -z "$local_build" ]]; then
  echo 'pubspec.yaml 里读不到 version: x.y.z+n' >&2
  exit 1
fi
# 与本地包区分：公开包用下一个 build number，两个二进制不会同号。
public_build=$((local_build + 1))
stamp="public-$(git -C "$repo_root" rev-parse --short HEAD) $(date +%Y-%m-%dT%H:%M)"

echo "公开包：$version ($public_build)，不带内置源"
mv "$pack" "$stash/builtin_sources.json"
# 代码里的种子同样要拿掉，否则 strings 还能挖出 20 个接口地址。
mv "$seeds" "$stash/builtin_seeds.g.dart"
cat > "$seeds" <<'DART'
// 公开包构建期间的占位：本版不随包带任何内置站点。
// 构建结束由 tool/build_macos_public.sh 的 trap 换回真清单。
import 'online_source.dart';

const builtinPackSites = <OnlineSite>[];
DART

flutter build macos --release \
  --build-number "$public_build" \
  --dart-define=SEEWOW_VERSION="$version" \
  --dart-define="SEEWOW_BUILD_STAMP=$stamp" \
  --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true \
  "$@"

# 不写死 App 名：真名是 seewow.app，靠大小写不敏感卷才让 SeeWow.app 能打开，
# 换到大小写敏感卷就找不到。判据与 CI 共用 tool/ci_public_build.sh verify 一处实现。
app="$(ls -d "$project_root"/build/macos/Build/Products/Release/*.app 2>/dev/null | head -1)"
[[ -n "$app" ]] || { echo '找不到构建产物 .app' >&2; exit 1; }
bash "$project_root/tool/ci_public_build.sh" verify "$app"
built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
built_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
echo "产物版本：$built_version ($built_number)"

out="$repo_root/dist/SeeWow-macos-$version-public-nosources.zip"
rm -f "$out" "$out.sha256"
ditto -c -k --norsrc --keepParent "$app" "$out"
# 同一道闸门也查符号链接：ditto 之后 X.framework/X 仍是链接，包才不会被撑成三倍。
python3 "$project_root/tool/check_macos_zip.py" "$out"
shasum -a 256 "$out" > "$out.sha256"
echo "$out"
