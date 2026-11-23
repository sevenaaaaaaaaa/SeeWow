import 'builtin_seeds.g.dart';

/// 「在线源」的站点模型。
///
/// 这里的种子取自真实 TVBox 配置里唯一可直连的一类：苹果CMS 采集站
/// （`?ac=videolist&wd=` 查询，返回 JSON/XML，播放地址直接是 m3u8/mp4）。
/// jar / js / py 爬虫不在其中，也不会被加载。
class OnlineSite {
  const OnlineSite({
    required this.id,
    required this.name,
    required this.api,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String api;
  final bool enabled;

  OnlineSite copyWith({String? name, String? api, bool? enabled}) => OnlineSite(
    id: id,
    name: name ?? this.name,
    api: api ?? this.api,
    enabled: enabled ?? this.enabled,
  );

  /// 去重键：同一个采集接口换个写法只留一个。
  String get hostKey {
    final uri = Uri.tryParse(api.trim());
    if (uri == null) return api.trim().toLowerCase();
    var path = uri.path.toLowerCase();
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return '${uri.host.toLowerCase()}/${path}';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'api': api,
    'enabled': enabled,
  };

  static OnlineSite? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'], name = value['name'], api = value['api'];
    if (id is! String || name is! String || api is! String) return null;
    final uri = Uri.tryParse(api.trim());
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    return OnlineSite(
      id: id,
      name: name,
      api: api,
      enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
    );
  }
}

/// 随包源包（`assets/sources/builtin_sources.json`）在代码里的镜像。
///
/// 实际的站点清单在 `builtin_seeds.g.dart`，由 `tool/gen_seeds.py` 生成：公开包
/// 构建时那个文件会被换成空表，二进制里连接口地址都搜不到。两条清单必须一致——
/// `builtin_sources_test.dart` 会比对它们的 api 集合。
const seedOnlineSites = builtinPackSites;

/// 保序去重，顺带丢掉接口地址相同的重复站点。
List<OnlineSite> dedupeSites(Iterable<OnlineSite> sites) {
  final seen = <String>{};
  return [
    for (final site in sites)
      if (seen.add(site.hostKey)) site,
  ];
}
