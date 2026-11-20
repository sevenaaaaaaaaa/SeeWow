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

/// 2026-11-20 从 qist/tvbox 的 jsm.json 里实测出来的 15 个直连采集站。
/// 其中「金蝉」与「789」指向同一个接口，去重后 14 个。
const seedOnlineSites = <OnlineSite>[
  OnlineSite(id: 'dytt', name: '电影天堂', api: 'http://caiji.dyttzyapi.com/api.php/provide/vod'),
  OnlineSite(id: 'tyys', name: '天涯', api: 'http://tyyszy.com/api.php/provide/vod'),
  OnlineSite(id: 'lzi', name: '量子', api: 'https://cj.lziapi.com/api.php/provide/vod/'),
  OnlineSite(id: 'ffzy', name: '非凡', api: 'http://ffzy.tv/api.php/provide/vod/'),
  OnlineSite(id: 'sony', name: '索尼', api: 'https://suoniapi.com/api.php/provide/vod/at/xml/'),
  OnlineSite(id: 'wolong', name: '卧龙资源', api: 'https://wolongzyw.com/api.php/provide/vod/?ac=list'),
  OnlineSite(id: 'uku', name: '尤酷', api: 'https://api.ukuapi.com/api.php/provide/vod/?ac=list'),
  OnlineSite(id: 'jisu', name: '极速资源', api: 'https://jszyapi.com/api.php/provide/vod/?ac=list'),
  OnlineSite(id: 'jianan', name: '建安采集', api: 'http://154.219.117.232:9981/jacloudapi.php/provide/vod'),
  OnlineSite(id: 'jinchan', name: '金蝉采集', api: 'https://zy.jinchancaiji.com/api.php/provide/vod'),
  OnlineSite(id: 'xiaomianyang', name: '小绵阳', api: 'https://vs.okcdn100.top/api.php/provide/vod'),
  OnlineSite(id: 'lv', name: '率率', api: 'https://suoniapi.com/api.php/provide/vod/?ac=list'),
  OnlineSite(id: 'baidu', name: '百度资源', api: 'https://api.apibdzy.com/api.php/provide/vod?ac=list'),
  OnlineSite(id: 'bfzy', name: '暴风资源', api: 'https://bfzyapi.com/api.php/provide/vod/?ac=list'),
];

/// 保序去重，顺带丢掉接口地址相同的重复站点。
List<OnlineSite> dedupeSites(Iterable<OnlineSite> sites) {
  final seen = <String>{};
  return [
    for (final site in sites)
      if (seen.add(site.hostKey)) site,
  ];
}
