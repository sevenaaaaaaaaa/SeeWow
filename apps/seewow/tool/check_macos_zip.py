#!/usr/bin/env python3
"""检查 macOS 发行 zip：框架的符号链接还在不在、包有没有被撑大。

背景：actions/upload-artifact 不保留符号链接。.app 里
X.framework/X 与 X.framework/Versions/Current/X 本来是指向 Versions/A 的链接，
往返一次就变成三份真文件：1.21.5 的 macOS 包因此是 535 项 / 318 MB
（本机干净产物 326 项 / 108 MB），下载从 42 MB 涨到 124 MB。

用法：python3 tool/check_macos_zip.py <zip>
通过退出 0，不通过打印问题项并退出 1。
"""

import stat
import sys
import zipfile

BUDGET = 150_000_000  # 干净产物约 108 MB，留 40% 余量
LINK_MAX = 4096       # 链接项存的是目标路径，几十字节；真文件至少几 MB


def is_link(info: zipfile.ZipInfo) -> bool:
    mode = info.external_attr >> 16
    return stat.S_ISLNK(mode)


def main(path: str) -> int:
    with zipfile.ZipFile(path) as zf:
        infos = zf.infolist()
    total = sum(i.file_size for i in infos)
    materialized = []
    for i in infos:
        parts = i.filename.split("/")
        # X.framework/<binary>：正常是链接；被写成真文件就是 upload-artifact 干的
        if len(parts) >= 2 and parts[-2].endswith(".framework") and "." not in parts[-1]:
            if not is_link(i) and i.file_size > LINK_MAX:
                materialized.append(i)
    print(f"{path}: {len(infos)} 项 · 解压后 {total / 1e6:.1f} MB · "
          f"被写成真文件的框架链接 {len(materialized)} 个")
    bad = False
    if materialized:
        bad = True
        print("失败：框架的符号链接被写成了真文件（upload-artifact 往返的痕迹）", file=sys.stderr)
        for i in sorted(materialized, key=lambda x: -x.file_size)[:6]:
            print(f"  {i.file_size:>10}  {i.filename}", file=sys.stderr)
    if total > BUDGET:
        bad = True
        print(f"失败：解压后 {total / 1e6:.1f} MB，超过 {BUDGET / 1e6:.0f} MB 上限", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法：python3 tool/check_macos_zip.py <zip>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
