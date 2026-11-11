import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';
import '../sources/json_api.dart';
import '../sources/native_bridge.dart';
import '../sources/subscription_reader.dart';

class LocalSubtitle {
  const LocalSubtitle(this.path, this.name);
  final String path, name;
}

/// Downloaded text stays in app storage; media and NAS files are never changed.
class SubtitleCache {
  SubtitleCache({this.directory});
  final Directory? directory;
  Future<Directory> _root() async =>
      directory ??
      Directory(
        '${(await getApplicationSupportDirectory()).path}/SeeWow/subtitles',
      );
  String _key(MediaItem item) =>
      sha1.convert(utf8.encode('${item.sourceId}/${item.id}')).toString();
  Future<LocalSubtitle> save(
    MediaItem item,
    String text, {
    String language = '',
  }) async {
    final bytes = utf8.encode(text);
    if (bytes.length > 2 * 1024 * 1024) throw const FormatException('字幕超过缓存上限');
    final root = await _root();
    final folder = await Directory('${root.path}/${_key(item)}')
        .create(recursive: true);
    final safeLanguage = RegExp(r'^[a-zA-Z0-9-]{1,16}$').hasMatch(language)
        ? language
        : 'und';
    final name =
        '$safeLanguage-${sha1.convert(bytes).toString().substring(0, 20)}.srt';
    final file = File('${folder.path}/$name');
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
    return LocalSubtitle(file.path, '缓存字幕 · $safeLanguage');
  }

  Future<List<LocalSubtitle>> list(MediaItem item) async {
    final folder = Directory('${(await _root()).path}/${_key(item)}');
    if (!await folder.exists()) return [];
    final files = <File>[];
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is File && entry.path.endsWith('.srt')) files.add(entry);
    }
    return [
      for (final file in files)
        LocalSubtitle(
          file.path,
          '缓存字幕 · ${file.uri.pathSegments.last.replaceFirst(RegExp(r'-[a-f0-9]{20}\.srt$'), '')}',
        ),
    ];
  }

  Future<void> clear() async {
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class SubtitleFiles {
  static const extensions = [
    'srt',
    'vtt',
    'ass',
    'ssa',
    'sub',
    'idx',
    'sup',
    'smi',
    'sami',
    'ttml',
    'dfxp',
    'sbv',
  ];
  static bool matches(String filename, String videoName) {
    final dot = videoName.lastIndexOf('.');
    if (dot < 1) return false;
    final stem = videoName.substring(0, dot).toLowerCase(),
        lower = filename.toLowerCase();
    return extensions.contains(lower.split('.').last) &&
        (lower.startsWith('$stem.') || lower.startsWith('$stem '));
  }

  static Future<List<LocalSubtitle>> discover(String locator) async {
    final uri = Uri.tryParse(locator);
    if (uri == null ||
        (uri.hasScheme &&
            uri.scheme != 'file' &&
            !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(locator)))
      return [];
    final file = uri.scheme == 'file' ? File.fromUri(uri) : File(locator);
    if (!await file.exists()) return [];
    final videoName = file.uri.pathSegments.last;
    final results = <LocalSubtitle>[];
    for (final dir in [
      file.parent,
      Directory('${file.parent.path}/Subs'),
      Directory('${file.parent.path}/subtitles'),
    ]) {
      if (!await dir.exists()) continue;
      var visited = 0;
      await for (final entry in dir.list(followLinks: false)) {
        if (++visited > 1000) break;
        if (entry is! File || !matches(entry.uri.pathSegments.last, videoName))
          continue;
        if (await entry.length() > 16 * 1024 * 1024) continue;
        results.add(LocalSubtitle(entry.path, entry.uri.pathSegments.last));
      }
    }
    results.sort((a, b) => a.name.compareTo(b.name));
    return results;
  }
}

class SubtitleCandidate {
  const SubtitleCandidate({
    required this.fileId,
    required this.filename,
    required this.language,
    this.release = '',
    this.hearingImpaired = false,
    this.machineTranslated = false,
    this.downloads = 0,
  });
  final int fileId, downloads;
  final String filename, language, release;
  final bool hearingImpaired, machineTranslated;
}

class OpenSubtitlesClient {
  OpenSubtitlesClient(
    String apiKey, {
    String token = '',
    Uri? base,
    this.reader = const SubscriptionReader(maxBytes: 2 * 1024 * 1024),
  }) : _api = JsonApi(
         base ?? Uri.parse('https://api.opensubtitles.com/api/v1'),
         headers: {
           'Api-Key': apiKey.trim(),
           'User-Agent': 'SeeWow v1.6.0',
           if (token.trim().isNotEmpty)
             'Authorization': 'Bearer ${token.trim()}',
         },
         maxBytes: 2 * 1024 * 1024,
       ) {
    if (apiKey.trim().isEmpty)
      throw const FormatException('请先配置 OpenSubtitles API Key');
  }
  final JsonApi _api;
  final SubscriptionReader reader;
  int? remaining;
  bool hasMore = false;
  static const credentialsKey = 'metadata.opensubtitles.credentials';
  static bool officialBase(Uri uri) =>
      uri.scheme == 'https' &&
      [
        'api.opensubtitles.com',
        'vip-api.opensubtitles.com',
      ].contains(uri.host) &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (!uri.hasPort || uri.port == 443);
  static Future<OpenSubtitlesClient> configured() async {
    try {
      final raw = await NativeBridge.secretRead(credentialsKey);
      if (raw == null)
        throw const FormatException('请先配置 OpenSubtitles API Key');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final base = Uri.parse(
        data['base'] as String? ?? 'https://api.opensubtitles.com/api/v1',
      );
      if (!officialBase(base)) throw const FormatException('字幕服务地址无效，请重新配置');
      return OpenSubtitlesClient(
        data['key'] as String,
        token: data['token'] as String? ?? '',
        base: base,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('字幕服务配置不可用，请重新配置');
    }
  }

  static Future<void> configure(
    String key, {
    String username = '',
    String password = '',
  }) async {
    if (key.trim().isEmpty)
      throw const FormatException('请填写 OpenSubtitles API Key');
    String token = '';
    var base = Uri.parse('https://api.opensubtitles.com/api/v1');
    if (username.trim().isNotEmpty || password.isNotEmpty) {
      if (username.trim().isEmpty || password.isEmpty)
        throw const FormatException('登录需要同时填写用户名和密码');
      final client = OpenSubtitlesClient(key);
      try {
        final result = await client._api.post('login', {
          'username': username.trim(),
          'password': password,
        });
        token = result['token'] as String? ?? '';
        if (token.isEmpty) throw const FormatException('登录未返回有效会话');
        if (result['base_url'] is String) {
          final host = result['base_url'] as String;
          final proposed = Uri.parse(
            host.startsWith('https://') ? host : 'https://$host',
          );
          if (!officialBase(proposed))
            throw const FormatException('字幕服务返回了未经信任的账号地址');
          base = proposed.replace(path: '/api/v1');
        }
      } finally {
        client.close();
      }
    }
    // Password is used once for login, never persisted with the library.
    await NativeBridge.secretWrite(
      credentialsKey,
      jsonEncode({'key': key.trim(), 'token': token, 'base': base.toString()}),
    );
  }

  Future<List<SubtitleCandidate>> search(
    MediaItem item, {
    String? query,
    String languages = '',
    int page = 1,
  }) async {
    final codes = languages
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .join(',');
    if (codes.isNotEmpty &&
        !RegExp(r'^[a-z]{2,3}(?:-[a-z]{2})?(?:,[a-z]{2,3}(?:-[a-z]{2})?)*$')
            .hasMatch(codes))
      throw const FormatException(
        '字幕语言填写 en、zh-cn、zh-tw、pt-br 等代码，用英文逗号分隔；留空搜索全部语言',
      );
    if (page < 1 || page > 500) throw const FormatException('页码超出范围');
    final imdb = item.metadata?.externalIds['imdb'] ?? '';
    final useId = query == null && RegExp(r'^tt\d+$').hasMatch(imdb);
    final result = await _api.get('subtitles', {
      if (useId)
        (item.kind == MediaKind.episode && item.metadata?.mediaType == 'tv'
            ? 'parent_imdb_id'
            : 'imdb_id'): imdb.substring(
          2,
        )
      else
        'query': (query ?? item.libraryTitle).trim(),
      if (item.season != null) 'season_number': '${item.season}',
      if (item.episode != null) 'episode_number': '${item.episode}',
      if (codes.isNotEmpty) 'languages': codes,
      'page': '$page',
      'order_by': 'download_count',
      'order_direction': 'desc',
    });
    if (result['data'] is! List) throw const FormatException('字幕服务没有返回有效的结果');
    hasMore = page < (result['total_pages'] as num? ?? page);
    final results = <SubtitleCandidate>[];
    for (final data in (result['data'] as List).whereType<Map>()) {
      final attributes = data['attributes'];
      if (attributes is! Map) continue;
      for (final file
          in (attributes['files'] as List? ?? []).whereType<Map>()) {
        if (file['file_id'] is! num) continue;
        results.add(
          SubtitleCandidate(
            fileId: (file['file_id'] as num).toInt(),
            filename: file['file_name']?.toString() ?? 'Subtitle',
            language: attributes['language']?.toString() ?? '',
            release: attributes['release']?.toString() ?? '',
            hearingImpaired: attributes['hearing_impaired'] == true,
            machineTranslated: attributes['machine_translated'] == true,
            downloads: (attributes['download_count'] as num? ?? 0).toInt(),
          ),
        );
      }
    }
    return results.take(100).toList();
  }

  Future<String> download(SubtitleCandidate candidate) async {
    final result = await _api.post('download', {
      'file_id': candidate.fileId,
      'sub_format': 'srt',
    });
    final uri = Uri.tryParse(result['link']?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty)
      throw const FormatException('字幕服务未返回安全的下载地址');
    remaining = (result['remaining'] as num?)?.toInt();
    // A separate anonymous, bounded transport never forwards account headers.
    final text = (await reader.read(uri.toString())).text
        .replaceFirst('\uFEFF', '');
    if (text.trimLeft().startsWith('<') ||
        (!text.contains('-->') && !text.contains('[Script Info]')))
      throw const FormatException('下载内容不是支持的文字字幕，请尝试其他版本');
    return text;
  }

  void close() => _api.close();
}
