import 'dart:convert';

/// TVBox 配置是**数据**，不是插件：这里只做分类与直链提取，绝不下载或执行
/// jar / js / py 爬虫。分类结果决定后面能不能接一个纯 HTTP 的采集站客户端。
enum TvBoxSiteKind { cms, directHttp, jarSpider, jsSpider, pySpider, unknown }

class TvBoxSite {
  const TvBoxSite({
    required this.key,
    required this.name,
    required this.kind,
    this.type,
    this.api,
    this.ext,
  });

  final String key;
  final String name;
  final TvBoxSiteKind kind;
  final int? type;
  final String? api;
  final String? ext;

  /// 只有直接 HTTP 的采集站能被本版请求；其余都要插件运行时。
  bool get playable =>
      kind == TvBoxSiteKind.cms || kind == TvBoxSiteKind.directHttp;
}

class TvBoxLiveEntry {
  const TvBoxLiveEntry({
    required this.name,
    required this.uri,
    this.group,
    this.epgUrl,
    this.viaProxy = false,
  });

  final String name;
  final Uri uri;
  final String? group;
  final String? epgUrl;

  /// 原始地址是 proxy:// 形式，已按 TVBox 约定解成直链。
  final bool viaProxy;
}

class TvBoxConfigReport {
  const TvBoxConfigReport({
    required this.sites,
    required this.lives,
    required this.parseCount,
    required this.spiderJar,
    required this.warnings,
    required this.notes,
  });

  final List<TvBoxSite> sites;
  final List<TvBoxLiveEntry> lives;
  final int parseCount;
  final String? spiderJar;
  final List<String> warnings;
  final List<String> notes;

  int countOf(TvBoxSiteKind kind) =>
      sites.where((site) => site.kind == kind).length;

  List<TvBoxSite> get playableSites =>
      sites.where((site) => site.playable).toList(growable: false);

  int get blockedCount => sites.length - playableSites.length;

  /// 一句话结论，界面直接显示，不用自己拼数字。
  String get digest {
    final parts = <String>[
      if (playableSites.isNotEmpty) '可直连 ${playableSites.length} 个站点',
      if (lives.isNotEmpty) '${lives.length} 条直播源',
      if (blockedCount > 0) '$blockedCount 个站点需要爬虫插件（已跳过）',
    ];
    if (parts.isEmpty) return '这份配置里没有本版能用的站内内容';
    return parts.join(' · ');
  }
}

/// 解析 TVBox 配置。只读字段，不执行任何脚本，不下载 spider jar。
class TvBoxConfig {
  static const maxSites = 20000;

  static TvBoxSiteKind classify(String api) {
    final value = api.trim();
    if (value.isEmpty) return TvBoxSiteKind.unknown;
    if (value.startsWith('csp_')) return TvBoxSiteKind.jarSpider;
    if (RegExp(r'\.js(?:\?|$)', caseSensitive: false).hasMatch(value)) {
      return TvBoxSiteKind.jsSpider;
    }
    if (RegExp(r'\.py(?:\?|$)', caseSensitive: false).hasMatch(value)) {
      return TvBoxSiteKind.pySpider;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final lower = value.toLowerCase();
      return lower.contains('api.php') || lower.contains('provide/vod')
          ? TvBoxSiteKind.cms
          : TvBoxSiteKind.directHttp;
    }
    return TvBoxSiteKind.unknown;
  }

  /// TVBox 的 `proxy://do=live&type=txt&ext=<base64 地址>`：`ext` 里是真实列表地址。
  static Uri? decodeProxyLive(String raw) {
    final text = raw.trim();
    if (!text.toLowerCase().startsWith('proxy://')) return null;
    final match = RegExp(r'[?&]?ext=([^&]+)').firstMatch(text.substring(8));
    final encoded = match?.group(1);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      var padded = encoded.replaceAll('-', '+').replaceAll('_', '/');
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      final uri = Uri.tryParse(utf8.decode(base64.decode(padded)).trim());
      if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
      if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
      return uri;
    } on FormatException {
      return null;
    }
  }

  static TvBoxConfigReport parse(String text, {required Uri baseUri}) {
    final body = text.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (body.isEmpty) throw const FormatException('配置内容为空');
    if (!body.startsWith('{')) {
      throw const FormatException('这不是 TVBox 的 JSON 配置；直播列表请走订阅导入');
    }
    dynamic data;
    try {
      data = jsonDecode(body);
    } on FormatException {
      throw const FormatException('配置不是有效 JSON；加密或伪装配置不支持');
    }
    if (data is! Map) throw const FormatException('配置顶层必须是对象');

    final warnings = <String>[];
    final notes = <String>[];
    final sites = <TvBoxSite>[];
    final lives = <TvBoxLiveEntry>[];

    final rawSites = data['sites'];
    if (rawSites is List) {
      for (final entry in rawSites) {
        if (sites.length >= maxSites) break;
        if (entry is! Map) continue;
        final api = entry['api'] is String ? entry['api'] as String : '';
        final rawName = entry['name'];
        sites.add(
          TvBoxSite(
            key: entry['key'] is String ? entry['key'] as String : '',
            name: rawName is String && rawName.trim().isNotEmpty
                ? rawName.trim()
                : '未命名站点',
            kind: classify(api),
            type: entry['type'] is int ? entry['type'] as int : null,
            api: api.trim().isEmpty ? null : api.trim(),
            ext: entry['ext'] is String ? entry['ext'] as String : null,
          ),
        );
      }
    }

    Uri? web(Object? value) {
      if (value is! String || value.trim().isEmpty) return null;
      final ref = Uri.tryParse(value.trim());
      if (ref == null) return null;
      final resolved = ref.hasScheme ? ref : baseUri.resolveUri(ref);
      return ['http', 'https'].contains(resolved.scheme) &&
              resolved.host.isNotEmpty &&
              resolved.userInfo.isEmpty
          ? resolved
          : null;
    }

    bool isProxy(Object? value) =>
        value is String && value.trim().toLowerCase().startsWith('proxy://');

    Uri? liveUri(Object? value, String name) {
      if (isProxy(value)) {
        final decoded = decodeProxyLive(value as String);
        if (decoded == null) {
          warnings.add('直播源「$name」的 proxy:// 地址解不出来，已跳过');
        }
        return decoded;
      }
      return web(value);
    }

    void addLive(Object? entry, {String group = ''}) {
      if (entry is! Map) return;
      final rawName = entry['name'];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : '未命名直播';
      final epg = web(entry['epg'])?.toString();
      final direct = liveUri(entry['url'], name);
      if (direct != null) {
        lives.add(
          TvBoxLiveEntry(
            name: name,
            uri: direct,
            group: group.isEmpty ? null : group,
            epgUrl: epg,
            viaProxy: isProxy(entry['url']),
          ),
        );
        return;
      }
      final channels = entry['channels'];
      if (channels is! List) {
        if (entry['url'] != null) {
          warnings.add('直播源「$name」没有可直连的地址，已跳过');
        }
        return;
      }
      for (final channel in channels) {
        if (channel is! Map) continue;
        final rawChannelName = channel['name'];
        final channelName =
            rawChannelName is String && rawChannelName.trim().isNotEmpty
            ? rawChannelName.trim()
            : name;
        final single = liveUri(channel['url'], channelName);
        if (single != null) {
          lives.add(
            TvBoxLiveEntry(
              name: channelName,
              uri: single,
              group: group.isEmpty ? null : group,
              epgUrl: web(channel['epg'])?.toString() ?? epg,
              viaProxy: isProxy(channel['url']),
            ),
          );
        }
        final alternatives = channel['urls'];
        if (alternatives is List) {
          for (final alternative in alternatives) {
            final resolved = liveUri(alternative, channelName);
            if (resolved == null) continue;
            lives.add(
              TvBoxLiveEntry(
                name: channelName,
                uri: resolved,
                group: group.isEmpty ? null : group,
                epgUrl: epg,
                viaProxy: isProxy(alternative),
              ),
            );
          }
        }
      }
    }

    final rawLives = data['lives'];
    if (rawLives is List) {
      for (final entry in rawLives) {
        final rawGroup = entry is Map ? entry['group'] : null;
        addLive(entry, group: rawGroup is String ? rawGroup : '');
      }
    }

    final parses = data['parses'];
    final parseCount = parses is List ? parses.length : 0;
    final spider = data['spider'];
    final spiderJar = spider is String && spider.trim().isNotEmpty
        ? spider.trim()
        : null;

    final jars = sites.where((s) => s.kind == TvBoxSiteKind.jarSpider).length;
    final js = sites.where((s) => s.kind == TvBoxSiteKind.jsSpider).length;
    final py = sites.where((s) => s.kind == TvBoxSiteKind.pySpider).length;
    if (jars > 0) {
      warnings.add('$jars 个站点依赖 jar 爬虫（csp_*），本版不加载插件，已跳过');
    }
    if (js > 0) {
      warnings.add('$js 个站点依赖 JS 爬虫，本版不执行脚本，已跳过');
    }
    if (py > 0) {
      warnings.add('$py 个站点依赖 Python 爬虫，已跳过');
    }
    if (parseCount > 0) {
      warnings.add('$parseCount 个外挂解析服务已忽略（需要网页解析环境）');
    }
    if (spiderJar != null) warnings.add('配置里的 spider 插件包未下载');
    if (data['proxy'] != null || data['rules'] != null || data['hosts'] != null) {
      warnings.add('配置里的代理、DNS 与规则字段已忽略');
    }
    if (lives.any((live) => live.viaProxy)) {
      notes.add('已把 proxy:// 直播源解成直链');
    }
    return TvBoxConfigReport(
      sites: sites,
      lives: lives,
      parseCount: parseCount,
      spiderJar: spiderJar,
      warnings: warnings,
      notes: notes,
    );
  }
}
