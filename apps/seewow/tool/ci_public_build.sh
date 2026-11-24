#!/bin/bash
# 公开包（上 GitHub Release 那一份）不带任何内置播放源 —— 构建前后的两件事。
#
# 为什么不能只传 --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true：
#   那个开关只让 App **运行时不加载**内置源，文件本身照旧打进包里，站点地址照旧编进
#   AOT 二进制（lib/domain/builtin_seeds.g.dart 是真表）。1.21.5 的公开 APK 就是这样
#   发出去的：unzip -l 能列出 3718 字节的 assets/sources/builtin_sources.json，
#   与本机预览包那份字节完全相同（docs/releases/1.21.5.md §3）。
#
# 本脚本做的两件事：
#   prep          构建前：把源包挪出工作区、把代码种子换成空表；
#   verify <产物> 构建后：扫产物 —— 源包文件、站点域名，命中任意一条就退出 1。
#
# 用法（CI 里 prep / verify 分开跑，中间的 build 用各平台原生命令）：
#   bash tool/ci_public_build.sh prep
#   flutter build macos --release --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true
#   bash tool/ci_public_build.sh verify build/macos/Build/Products/Release/seewow.app
#
# 也可以一条命令跑完（本机用，结束会还原工作区）：
#   bash tool/ci_public_build.sh build macos
#
# 注意：prep 不还原 —— CI 的 runner 是一次性的，还原反而会把源包塞回构建树。

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

pack="assets/sources/builtin_sources.json"
seeds="lib/domain/builtin_seeds.g.dart"
stash="${TMPDIR:-/tmp}/seewow-public-stash"

# 取样域名：源包 v2 里前两个站的 host。verify 扫的是编译产物，这两个都搜不到就说明
# 整张表没进二进制（与 build_macos_public.sh 取样的那一对一致）。按固定字符串搜，
# 不走正则 —— 正则里的转义写错会让这个闸门永远为绿。
sample_hosts=('zuidapi.com' '155api.com')

die() { echo "失败：$*" >&2; exit 1; }

prep() {
  [[ -f "$pack" ]] || die "找不到 $pack —— 先确认工作区是干净的"
  [[ -f "$seeds" ]] || die "找不到 $seeds —— 先跑 tool/gen_seeds.py"
  rm -rf "$stash" && mkdir -p "$stash"
  mv "$pack" "$stash/builtin_sources.json"
  mv "$seeds" "$stash/builtin_seeds.g.dart"
  cat > "$seeds" <<'DART'
// 公开包构建期间的占位：本版不随包带任何内置站点。
// 由 tool/ci_public_build.sh 在构建前写入；本机构建用真表，不要提交这一版。
import 'online_source.dart';

const builtinPackSites = <OnlineSite>[];
DART
  # 版本与构建戳：CI 的 flutter build 不读 pubspec 的版本，BuildInfo 会把默认值印在
  # 关于页上（1.21.5 的公开包就是这么显示旧号的）。写成 defines 文件交给
  # --dart-define-from-file，五个平台同一份，不依赖各 shell 的变量语法。
  local version stamp
  version="$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)"
  [[ -n "$version" ]] || die "pubspec.yaml 里读不到 version: x.y.z+n"
  stamp="$(git rev-parse --short HEAD 2>/dev/null || echo nogit) $(date -u +%Y-%m-%dT%H:%M)"
  mkdir -p build
  printf '{"SEEWOW_VERSION":"%s","SEEWOW_BUILD_STAMP":"%s"}\n' "$version" "$stamp" > build/public_defines.json
  echo "prep: 源包与代码种子已移出工作区（产物将按 ${#sample_hosts[@]} 个域名取样）"
  echo "prep: build/public_defines.json = $version · $stamp"
}

restore() {
  [[ -f "$stash/builtin_sources.json" ]] && mv "$stash/builtin_sources.json" "$pack"
  [[ -f "$stash/builtin_seeds.g.dart" ]] && mv "$stash/builtin_seeds.g.dart" "$seeds"
  rm -rf "$stash"
  return 0
}

# verify <产物路径>：目录、.app、.apk 都能吃
verify() {
  local artifact="$1" scan="$1" tmp="" bad=0 host hits
  [[ -e "$artifact" ]] || die "产物不存在：$artifact"
  if [[ "$artifact" == *.apk ]]; then
    tmp="$(mktemp -d)"
    unzip -q "$artifact" -d "$tmp" || die "$artifact 解不开"
    scan="$tmp"
  fi
  hits="$(find "$scan" -name 'builtin_sources.json' -print 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "失败：产物里还有源包文件" >&2
    echo "$hits" >&2
    bad=1
  fi
  for host in "${sample_hosts[@]}"; do
    if grep -rlaF "$host" "$scan" >/dev/null 2>&1; then
      echo "失败：产物里还能搜到站点地址 $host" >&2
      grep -rlaF "$host" "$scan" 2>/dev/null | head -3 >&2
      bad=1
    fi
  done
  if [[ -n "$tmp" ]]; then rm -rf "$tmp"; fi
  if [[ "$bad" -ne 0 ]]; then
    exit 1
  fi
  echo "verify: $artifact 干净（无源包文件、无站点地址）"
}

build_local() {
  local platform="$1"; shift
  local artifact=""
  trap restore EXIT INT TERM
  prep
  case "$platform" in
    macos)
      flutter build macos --release --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true "$@"
      artifact="$(ls -d build/macos/Build/Products/Release/*.app 2>/dev/null | head -1)"
      ;;
    ios)
      flutter build ios --release --no-codesign --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true "$@"
      artifact="build/ios/iphoneos/Runner.app"
      ;;
    *)
      die "本机能跑的只有 macos / ios；其余平台交给 CI"
      ;;
  esac
  [[ -n "$artifact" ]] || die "没找到构建产物"
  verify "$artifact"
}

case "${1:-}" in
  prep)    prep ;;
  restore) restore ;;
  verify) [[ -n "${2:-}" ]] || die "用法：$0 verify <产物路径>"; verify "$2" ;;
  build)  [[ -n "${2:-}" ]] || die "用法：$0 build macos|ios"; shift; build_local "$@" ;;
  *)      die "用法：$0 prep | verify <产物路径> | build macos|ios" ;;
esac
