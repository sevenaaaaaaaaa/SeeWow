#!/usr/bin/env python3
"""从 assets/sources/builtin_sources.json 生成 lib/domain/builtin_seeds.g.dart。

为什么要多这一层：公开包（上 GitHub 那份）不能带任何播放源。只把 JSON 挪走是不够的——
`seedOnlineSites` 是编译进二进制的常量，`strings` 一样能挖出 20 个接口地址。
所以种子单独放进一个生成文件，公开包构建时把它整体换成空表，二进制里就真的没有源了。

用法：
    python3 tool/gen_seeds.py            # 从 JSON 重新生成
"""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
pack = root / "assets/sources/builtin_sources.json"
out = root / "lib/domain/builtin_seeds.g.dart"

data = json.loads(pack.read_text(encoding="utf-8"))
sites = data["sites"]

lines = [
    "// GENERATED FILE — 由 tool/gen_seeds.py 从 assets/sources/builtin_sources.json 生成。",
    "// 不要手改；改源包后重跑 tool/gen_seeds.py。",
    "//",
    "// 公开包构建（tool/build_macos_public.sh）会把本文件换成空表，",
    "// 让二进制里连字符串都搜不到站点地址。",
    "",
    "import 'online_source.dart';",
    "",
    f"/// 源包 v{data.get('packVersion', '?')} 在代码里的镜像：{len(sites)} 个站点。",
    "const builtinPackSites = <OnlineSite>[",
]
for site in sites:
    lines.append(
        "  OnlineSite("
        f"id: '{site['id']}', "
        f"name: '{site['name']}', "
        f"api: '{site['api']}'"
        "),"
    )
lines.append("];")
lines.append("")

out.write_text("\n".join(lines), encoding="utf-8")
print(f"{out.relative_to(root)}: {len(sites)} sites")
