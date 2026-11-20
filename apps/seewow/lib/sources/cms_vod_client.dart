import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'subscription_reader.dart';

/// 苹果CMS（MacCMS v10）采集站的纯 HTTP 客户端。
///
/// 这是 TVBox 配置里唯一能被本版吃下的一类站点：接口是普通的
/// `?ac=videolist&wd=` 查询，返回 JSON 或 XML，播放地址直接就是 m3u8 / mp4。
/// 依赖 jar / js / py 爬虫的站点不在这里处理，也不会被下载或执行。
class CmsVodCategory {
  const CmsVodCategory(this.id, this.name);
  final int id;
  final String name;
}

class CmsVodEpisode {
  const CmsVodEpisode(this.name, this.url);
  final String name;
  final String url;

  /// 只有真正的媒体地址才能直接喂给播放器；分享页 / 播放器页需要网页解析，
  /// 本版没有解析环境，所以单独标出来。
  bool get directPlay => CmsVodClient.isDirectMediaUrl(url);
}

class CmsVodSource {
  const CmsVodSource(this.from, this.episodes);
  final String from;
  final List<CmsVodEpisode> episodes;

  bool get playable => episodes.any((episode) => episode.directPlay);

  List<CmsVodEpisode> get directEpisodes =>
      episodes.where((episode) => episode.directPlay).toList(growable: false);
}

class CmsVodItem {
  const CmsVodItem({
    required this.id,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.typeName = '',
    this.year = '',
    this.area = '',
    this.lang = '',
    this.actor = '',
    this.director = '',
    this.content = '',
    this.playFrom = '',
    this.playUrl = '',
  });

  final String id, name, pic, remarks, typeName, year, area, lang;
  final String actor, director, content, playFrom, playUrl;

  List<CmsVodSource> get sources => CmsVodClient.splitPlayUrl(playFrom, playUrl);

  bool get hasPlayableSource => sources.any((source) => source.playable);
}

class CmsVodClient {
  CmsVodClient(
    String api, {
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = 8 * 1024 * 1024,
    HttpClient? httpClient,
  }) : _api = Uri.parse(api.trim()),
       _client = httpClient ?? HttpClient() {
    SubscriptionReader.validateWebUri(_api);
    if (_api.hasFragment) throw const FormatException('采集站地址不要带 # 片段');
    if (_isLocalHost(_api.host)) {
      throw const FormatException('采集站地址指向本机或局域网，请填写公网地址');
    }
    _client.connectionTimeout = timeout;
  }

  final Uri _api;
  final Duration timeout;
  final int maxBytes;
  final HttpClient _client;

  Uri get api => _api;

  static bool _isLocalHost(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || name.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(name);
    if (address == null) return false;
    return SubscriptionReader.isLocalAddress(address);
  }

  void close() => _client.close(force: true);

  /// 苹果CMS 用 $$$ 分隔线路、# 分隔集、$ 分隔集名与地址。
  static const String sourceSeparator = r'$$$';
  static const String entrySeparator = r'$';

  Uri _request(Map<String, String> query) {
    final merged = <String, String>{};
    _api.queryParameters.forEach((key, value) => merged[key] = value);
    merged.addAll(query);
    return _api.replace(queryParameters: merged);
  }

  Future<String> _get(Map<String, String> query) async {
    final url = _request(query);
    final request = await _client.getUrl(url).timeout(timeout);
    request.followRedirects = true;
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    request.headers.set(HttpHeaders.userAgentHeader, 'okhttp/3.15');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      throw HttpException(
        '采集站返回 HTTP ${response.statusCode}',
        uri: url,
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw const FormatException('采集站返回内容超过大小限制');
      }
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  Future<List<CmsVodItem>> search(String keyword, {int page = 1}) async {
    final word = keyword.trim();
    if (word.isEmpty) return const [];
    return parseItems(
      await _get({'ac': 'videolist', 'wd': word, 'pg': '$page'}),
    );
  }

  Future<List<CmsVodItem>> latest({int page = 1}) => list(page: page);

  /// 按分类拉一页：`t` 是苹果CMS 的 type_id，短剧站通常单独给一个分类。
  Future<List<CmsVodItem>> list({int? categoryId, int page = 1}) async {
    return parseItems(
      await _get({
        'ac': 'videolist',
        'pg': '$page',
        if (categoryId != null && categoryId > 0) 't': '$categoryId',
      }),
    );
  }

  Future<CmsVodItem?> detail(String id) async {
    final items = parseItems(await _get({'ac': 'detail', 'ids': id}));
    return items.isEmpty ? null : items.first;
  }

  Future<List<CmsVodCategory>> categories() async =>
      parseCategories(await _get({'ac': 'list'}));

  /// JSON 与 XML 两种返回都能读；判断依据是正文第一个非空字符。
  static List<CmsVodItem> parseItems(String body) {
    final text = body.trim();
    if (text.isEmpty) return const [];
    if (text.startsWith('{') || text.startsWith('[')) {
      final data = jsonDecode(text);
      final list = data is Map ? data['list'] : null;
      if (list is! List) return const [];
      final items = <CmsVodItem>[];
      for (final entry in list) {
        if (entry is! Map) continue;
        String field(String key) {
          final value = entry[key];
          if (value is String) return value;
          return value == null ? '' : '$value';
        }

        final item = CmsVodItem(
          id: field('vod_id'),
          name: field('vod_name'),
          pic: field('vod_pic'),
          remarks: field('vod_remarks'),
          typeName: field('type_name'),
          year: field('vod_year'),
          area: field('vod_area'),
          lang: field('vod_lang'),
          actor: field('vod_actor'),
          director: field('vod_director'),
          content: field('vod_content'),
          playFrom: field('vod_play_from'),
          playUrl: field('vod_play_url'),
        );
        if (item.name.isNotEmpty) items.add(item);
      }
      return items;
    }
    if (text.startsWith('<')) return _parseXmlItems(text);
    throw const FormatException('采集站返回的内容不是 JSON 也不是 XML');
  }

  static List<CmsVodItem> _parseXmlItems(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException {
      throw const FormatException('采集站返回的 XML 无法解析');
    }
    final items = <CmsVodItem>[];
    for (final video in document.findAllElements('video')) {
      String field(String name) {
        final node = video.findElements(name).firstOrNull;
        return node == null ? '' : node.innerText.trim();
      }

      final flags = <String>[];
      final urls = <String>[];
      for (final dd in video.findAllElements('dd')) {
        flags.add(dd.getAttribute('flag') ?? '');
        urls.add(dd.innerText.trim());
      }
      final item = CmsVodItem(
        id: field('id'),
        name: field('name'),
        pic: field('pic'),
        remarks: field('note'),
        typeName: field('type'),
        year: field('year'),
        area: field('area'),
        lang: field('lang'),
        actor: field('actor'),
        director: field('director'),
        content: field('des'),
        playFrom: flags.join(sourceSeparator),
        playUrl: urls.join(sourceSeparator),
      );
      if (item.name.isNotEmpty) items.add(item);
    }
    return items;
  }

  static List<CmsVodCategory> parseCategories(String body) {
    final text = body.trim();
    if (text.startsWith('{')) {
      final data = jsonDecode(text);
      final list = data is Map ? data['class'] : null;
      if (list is! List) return const [];
      final categories = <CmsVodCategory>[];
      for (final entry in list) {
        if (entry is! Map) continue;
        final id = entry['type_id'];
        final name = entry['type_name'];
        categories.add(
          CmsVodCategory(
            id is int ? id : int.tryParse('$id') ?? 0,
            name is String ? name : '未分类',
          ),
        );
      }
      return categories;
    }
    if (text.startsWith('<')) {
      try {
        return XmlDocument.parse(text)
            .findAllElements('ty')
            .map(
              (node) => CmsVodCategory(
                int.tryParse(node.getAttribute('id') ?? '') ?? 0,
                node.innerText.trim(),
              ),
            )
            .toList();
      } on XmlException {
        throw const FormatException('采集站返回的 XML 无法解析');
      }
    }
    return const [];
  }

  /// 直接可播的判据：HTTP(S) 且路径像媒体文件。Youku / 腾讯 / 爱奇艺这类
  /// 外链页会被判成不可直连——它们要靠网页解析，本版不做。
  static bool isDirectMediaUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return false;
    if (uri.host.isEmpty) return false;
    const pageHosts = [
      'youku.com',
      'v.qq.com',
      'iqiyi.com',
      'bilibili.com',
      'mgtv.com',
      'le.com',
      'sohu.com',
      'pptv.com',
      '1905.com',
    ];
    final host = uri.host.toLowerCase();
    if (pageHosts.any((page) => host == page || host.endsWith('.$page'))) {
      return false;
    }
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.flv') ||
        lower.contains('.mkv') ||
        lower.contains('.ts?') ||
        RegExp(r'\.ts$').hasMatch(lower);
  }

  static List<CmsVodSource> splitPlayUrl(String from, String url) {
    if (url.trim().isEmpty) return const [];
    final groups = url.split(sourceSeparator);
    final names = from.split(sourceSeparator);
    final result = <CmsVodSource>[];
    for (var index = 0; index < groups.length; index++) {
      final episodes = <CmsVodEpisode>[];
      for (final raw in groups[index].split('#')) {
        final entry = raw.trim();
        if (entry.isEmpty) continue;
        final separator = entry.indexOf(entrySeparator);
        if (separator < 0) {
          if (entry.startsWith('http')) {
            episodes.add(
              CmsVodEpisode('第${episodes.length + 1}集', entry),
            );
          }
          continue;
        }
        final name = entry.substring(0, separator).trim();
        final link = entry.substring(separator + 1).trim();
        if (link.isEmpty) continue;
        episodes.add(CmsVodEpisode(name.isEmpty ? '正片' : name, link));
      }
      if (episodes.isEmpty) continue;
      final label = index < names.length ? names[index].trim() : '';
      result.add(
        CmsVodSource(
          label.isEmpty ? '线路${index + 1}' : label,
          episodes,
        ),
      );
    }
    return result;
  }
}
