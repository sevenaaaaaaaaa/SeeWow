import 'dart:convert';

import 'iptv.dart';

class SubscriptionLink {
  const SubscriptionLink(this.name, this.uri, {this.epgUrl});
  final String name;
  final Uri uri;
  final String? epgUrl;
}

class SubscriptionPreview {
  const SubscriptionPreview({
    required this.uri,
    this.channels = const [],
    this.links = const [],
    this.warnings = const [],
    this.epgUrl,
  });
  final Uri uri;
  final List<IPTVChannel> channels;
  final List<SubscriptionLink> links;
  final List<String> warnings;
  final String? epgUrl;
}

/// A deliberately small data schema, never a script/plugin interpreter.
class SubscriptionParser {
  static const maxEntries = 10000;

  static SubscriptionPreview parse(
    String text, {
    required Uri uri,
    required String playlistId,
  }) {
    text = text.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (text.startsWith('<'))
      throw const FormatException('这是网页或 XML 文件，请提供播放列表或配置文件');
    final warnings = <String>{};
    final channels = <IPTVChannel>[];
    final links = <SubscriptionLink>[];
    var visited = 0;
    String? epg;

    Uri? web(dynamic value) {
      if (value is! String || value.trim().isEmpty) return null;
      final ref = Uri.tryParse(value.trim());
      if (ref == null) return null;
      if (!ref.hasScheme &&
          !RegExp(
            r'^(?:/|\./|\.\./)|^[^\s<>]+\.(?:json|m3u8?|txt|mp4|mkv|ts)(?:[?#]|$)',
            caseSensitive: false,
          ).hasMatch(value.trim()))
        return null;
      final result = uri.resolveUri(ref);
      return ['http', 'https'].contains(result.scheme) &&
              result.host.isNotEmpty &&
              result.userInfo.isEmpty
          ? result
          : null;
    }

    void tick() {
      if (++visited > maxEntries) throw const FormatException('条目过多，请拆分列表后导入');
    }

    void channel(
      String name,
      dynamic value, {
      String group = '未分组',
      String logo = '',
      String tvgId = '',
    }) {
      tick();
      final url = web(value);
      if (url == null || (value is String && value.contains('|'))) {
        warnings.add('已跳过不支持的地址；仅导入 HTTP(S) 直接播放地址');
        return;
      }
      channels.add(
        IPTVChannel(
          id: '',
          playlistId: playlistId,
          name: name.isEmpty ? '未命名频道' : name,
          url: url.toString(),
          group: group,
          logo: web(logo)?.toString() ?? '',
          tvgId: tvgId,
        ),
      );
    }

    void link(dynamic value) {
      tick();
      if (value is! Map) return;
      final target = web(value['url']);
      if (target == null) {
        warnings.add('已跳过无效配置地址；配置不能读取本地文件');
        return;
      }
      links.add(
        SubscriptionLink(
          value['name'] is String ? value['name'] : '未命名配置',
          target,
          epgUrl: web(value['epg'])?.toString(),
        ),
      );
    }

    void rows(List list, String group, [int depth = 0]) {
      if (depth > 8) throw const FormatException('列表嵌套过深');
      for (final row in list) {
        tick();
        if (row is! Map) continue;
        final name = row['name'] is String ? row['name'] as String : '';
        if (row['channels'] is List) {
          rows(row['channels'] as List, name.isEmpty ? group : name, depth + 1);
        } else if (row['url'] is String) {
          channel(
            name,
            row['url'],
            group: row['group'] is String ? row['group'] : group,
            logo: row['logo'] is String ? row['logo'] : '',
            tvgId: row['tvg-id'] is String ? row['tvg-id'] : '',
          );
        } else if (row['urls'] is List) {
          // Inline channel alternatives, explicitly represented as URL strings.
          for (final url in row['urls'] as List) {
            channel(name, url, group: group);
          }
        }
      }
    }

    if (text.startsWith('{') || text.startsWith('[')) {
      _checkJsonDepth(text);
      dynamic data;
      try {
        data = jsonDecode(text);
      } on FormatException {
        throw const FormatException('JSON 格式无效；不支持加密或伪装配置');
      }
      if (data is List) {
        rows(data, '未分组');
      } else if (data is Map) {
        if (['sites', 'spider', 'parses'].any(data.containsKey)) {
          warnings.add('点播站点、爬虫和解析插件不受支持，不会下载或执行');
        }
        if ([
          'headers',
          'proxy',
          'rules',
          'hosts',
          'doh',
          'ads',
        ].any(data.containsKey)) {
          warnings.add('配置中的请求头、代理、DNS 和执行规则已忽略');
        }
        epg = web(data['epg'])?.toString();
        if (data['urls'] is List) {
          for (final entry in data['urls'] as List) {
            link(entry);
          }
        }
        if (data['channels'] is List) rows(data['channels'] as List, '未分组');
        if (data['lives'] is List) {
          for (final live in data['lives'] as List) {
            if (live is Map && live['channels'] is List) {
              rows(
                live['channels'] as List,
                live['name'] is String ? live['name'] : '未分组',
              );
            } else {
              link(live);
            }
          }
        }
      }
    } else if (text.startsWith('#EXTM3U') || text.contains('#EXTINF:')) {
      if (text.contains('#EXT-X-'))
        throw const FormatException('这是单个视频的 HLS 清单，请导入频道列表');
      final headerEpg = RegExp(
        r'''(?:url-tvg|x-tvg-url)\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(text);
      epg = web(headerEpg?.group(1))?.toString();
      if (text.contains('#EXTVLCOPT') || text.contains('#KODIPROP')) {
        warnings.add('此列表包含播放器扩展参数；本版忽略这些参数，部分频道可能无法播放');
      }
      for (final entry in M3UParser.parse(
        text,
        playlistId: playlistId,
        baseUri: uri,
      )) {
        channel(
          entry.name,
          entry.url,
          group: entry.group,
          logo: entry.logo,
          tvgId: entry.tvgId,
        );
      }
    } else {
      var group = '未分组';
      for (final raw in const LineSplitter().convert(text)) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final comma = line.indexOf(',');
        if (comma < 1) continue;
        final name = line.substring(0, comma).trim();
        final value = line.substring(comma + 1).trim();
        if (value == '#genre#') {
          group = name;
          continue;
        }
        // A TXT row represents one direct URL, never an executable expression.
        channel(name, value, group: group);
      }
    }
    final stable = M3UParser.stableIds(channels, playlistId);
    if (stable.isEmpty && links.isEmpty && warnings.isEmpty)
      throw const FormatException(
        '未找到支持的频道或配置；支持 M3U、名称逗号地址 TXT，以及 channels / lives / urls JSON',
      );
    return SubscriptionPreview(
      uri: uri,
      channels: stable,
      links: links,
      warnings: warnings.toList(),
      epgUrl: epg,
    );
  }

  static void _checkJsonDepth(String text) {
    var depth = 0;
    var inString = false, escaped = false;
    for (final code in text.codeUnits) {
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 92) {
          escaped = true;
        } else if (code == 34) {
          inString = false;
        }
      } else if (code == 34) {
        inString = true;
      } else if (code == 123 || code == 91) {
        if (++depth > 32) throw const FormatException('JSON 嵌套过深，请拆分配置');
      } else if (code == 125 || code == 93) {
        depth--;
      }
    }
  }
}
