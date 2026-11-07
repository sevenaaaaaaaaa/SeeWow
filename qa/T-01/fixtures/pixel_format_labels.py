#!/usr/bin/env python3
"""case-09 的比对器：window.rs 的 MTLPixelFormat 映射 vs 本机 Metal SDK 头文件。

证明什么：ADR-0010 §4 要求面板「如实标出证据」；面板上的 pixfmt 名字来自 window.rs 的
metal_pixel_format_name()。把 RGBA/BGRA 弄反，面板就会报出一个不存在的格式，证据失真。

怎么判：以 SDK 头文件 MTLPixelFormat.h 的枚举值为真值，逐条比对 name（大小写无关）。
退出码：0 一致 / 1 有偏差 / 2 找不到头文件。
"""
import os
import re
import subprocess
import sys

repo = os.environ["QA_REPO"]
win = os.path.join(repo, "apps/seewow-rs/crates/player/src/window.rs")

sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True).stdout.strip()
header = os.path.join(sdk, "System/Library/Frameworks/Metal.framework/Headers/MTLPixelFormat.h")
if not os.path.isfile(header):
    print(f"  [blocked] 找不到 Metal 头文件：{header}")
    sys.exit(2)
print(f"  [info] 真值来源：{header}")

truth = {}
for line in open(header, encoding="utf-8", errors="ignore"):
    m = re.search(r"MTLPixelFormat([A-Za-z0-9_]+).*=\s*(\d+)\s*,", line)
    if m:
        truth[int(m.group(2))] = m.group(1).lower()

src = open(win, encoding="utf-8").read()
mapping = {int(n): name for n, name in re.findall(r'(\d+)\s*=>\s*"([A-Za-z0-9_]+)"\.to_string\(\)', src)}
if not mapping:
    print("  [FAIL] window.rs 里没找到 数值 => 名字 的映射表")
    sys.exit(1)

failed = 0
for number in sorted(mapping):
    name = mapping[number].lower()
    if number not in truth:
        print(f"  [info] SDK 里没有 {number}，跳过")
        continue
    if name == truth[number]:
        print(f"  [ok]   MTLPixelFormat {number} = {mapping[number]}（与 SDK 一致）")
    else:
        failed += 1
        print(f"  [FAIL] MTLPixelFormat {number} 标成「{mapping[number]}」，SDK 里是「{truth[number]}」")

if mapping.get(94, "").lower() == "bgr10a2unorm":
    print("  [ok]   本机实测格式 94 → bgr10a2Unorm 有映射")
else:
    failed += 1
    print("  [FAIL] 94 没有映射成 bgr10a2Unorm（本机 mpv 报的就是这个格式）")

print(f"\ncase-09: 映射 {len(mapping)} 条，偏差 {failed} 条")
sys.exit(0 if failed == 0 else 1)
