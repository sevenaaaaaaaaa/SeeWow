#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$project_root/../.." && pwd)"
cd "$project_root"
flutter build ios --release --no-codesign "$@"

app_path="$project_root/build/ios/iphoneos/Runner.app"
build_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Info.plist")
supported_platform=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$app_path/Info.plist")
if [[ "$supported_platform" != 'iPhoneOS' ]]; then
  echo 'Expected a device build, refusing to package a simulator app.' >&2
  exit 1
fi
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/seewow-ios-ipa.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$staging_dir/Payload" "$repo_root/dist"
ditto --norsrc "$app_path" "$staging_dir/Payload/SeeWow.app"
ipa_path="$repo_root/dist/SeeWow-iOS-$build_version-arm64-unsigned.ipa"
ditto -c -k --norsrc --keepParent "$staging_dir/Payload" "$ipa_path"
unzip -tq "$ipa_path"
shasum -a 256 "$ipa_path" > "$ipa_path.sha256"
echo "$ipa_path"
