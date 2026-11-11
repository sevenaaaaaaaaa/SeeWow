import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import '../sources/native_bridge.dart';
import 'metadata_transport.dart';

/// Declarative JSON field mapping only; never executes source-supplied code.
class CustomScraperProfile {
  CustomScraperProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.kinds = const ['movie', 'episode', 'other'],
    this.category = '',
    this.searchPath = 'search',
    this.detailsPath = '',
    this.searchQuery = const {
      'q': '{query}',
      'type': '{kind}',
      'language': '{language}',
    },
    this.resultsPath = 'results',
    this.detailsRoot = '',
    this.fields = const {
      'id': 'id',
      'title': 'title',
      'overview': 'overview',
      'posterUrl': 'posterUrl',
      'year': 'year',
    },
    this.authHeader = 'Authorization',
    this.authPrefix = 'Bearer ',
    this.allowLan = false,
  });
  final String id,
      name,
      baseUrl,
      category,
      searchPath,
      detailsPath,
      resultsPath,
      detailsRoot,
      authHeader,
      authPrefix;
  final List<String> kinds;
  final Map<String, String> searchQuery, fields;
  final bool allowLan;
  static const fieldNames = {
    'id',
    'adult',
    'title',
    'originalTitle',
    'overview',
    'year',
    'genres',
    'posterUrl',
    'backdropUrl',
    'originalLanguage',
    'language',
    'countries',
    'people',
    'ratings',
    'localized',
    'alternativeTitles',
  };
  static final example = CustomScraperProfile(
    id: 'my-video-api',
    name: '我的影视资料',
    baseUrl: 'https://metadata.example.com/api',
  );
  void validate() {
    MetadataTransport.endpoint(baseUrl);
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id) ||
        name.trim().isEmpty ||
        name.length > 80)
      throw const FormatException('配置 ID 使用 1–64 位字母、数字、下划线或短横线，名称不可为空');
    if (kinds.isEmpty ||
        kinds.any((k) => !['movie', 'episode', 'other'].contains(k)))
      throw const FormatException('视频类型 kinds 为 movie、episode、other 的非空列表');
    if (category.length > 100 ||
        searchQuery.length > 20 ||
        fields.length > 25 ||
        fields.keys.any((key) => !fieldNames.contains(key)) ||
        !fields.containsKey('title'))
      throw const FormatException('类型或字段映射无效；仅映射支持的资料字段，title 必填');
    for (final path in [searchPath, if (detailsPath.isNotEmpty) detailsPath]) {
      if (path.length > 500 ||
          path.startsWith('/') ||
          path.contains('..') ||
          path.contains(':') ||
          path.contains('?') ||
          path.contains('#') ||
          path.contains('\\'))
        throw const FormatException('接口路径应为服务根目录下的相对路径，不含查询参数');
      _checkTemplates(path, path == searchPath ? const {} : const {'id'});
    }
    if (detailsPath.isNotEmpty && !detailsPath.contains('{id}'))
      throw const FormatException('详情路径必须包含 {id}');
    for (final value in searchQuery.values) {
      if (value.length > 500) throw const FormatException('查询模板过长');
      _checkTemplates(value, const {
        'query',
        'kind',
        'category',
        'language',
        'year',
        'season',
        'episode',
      });
    }
    for (final path in [resultsPath, detailsRoot, ...fields.values]) {
      if (path.length > 200 ||
          (path.isNotEmpty &&
              !RegExp(r'^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$').hasMatch(path)))
        throw const FormatException('JSON 路径使用点分隔的字段名或数组索引，不支持表达式');
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9-]{0,63}$').hasMatch(authHeader) ||
        [
          'host',
          'cookie',
          'connection',
          'content-length',
          'transfer-encoding',
          'content-type',
        ].contains(authHeader.toLowerCase()) ||
        authPrefix.length > 40 ||
        authPrefix.contains(RegExp(r'[\r\n]')))
      throw const FormatException('认证头名称或前缀无效');
  }

  static void _checkTemplates(String text, Set<String> allowed) {
    final rest = text.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) {
      if (!allowed.contains(m[1])) throw const FormatException('模板包含未知占位符');
      return '';
    });
    if (rest.contains('{') || rest.contains('}'))
      throw const FormatException('模板占位符无效');
  }

  String get credentialKey =>
      'metadata.custom.key.${sha256.convert(utf8.encode(jsonEncode([id, baseUrl, authHeader, authPrefix])))}';
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'kinds': kinds,
    'category': category,
    'searchPath': searchPath,
    'detailsPath': detailsPath,
    'searchQuery': searchQuery,
    'resultsPath': resultsPath,
    'detailsRoot': detailsRoot,
    'fields': fields,
    'authHeader': authHeader,
    'authPrefix': authPrefix,
    'allowLan': allowLan,
  };
  factory CustomScraperProfile.fromJson(Map<String, dynamic> j) =>
      CustomScraperProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        baseUrl: j['baseUrl'] as String,
        kinds: (j['kinds'] as List? ?? ['movie', 'episode', 'other'])
            .cast<String>(),
        category: j['category'] as String? ?? '',
        searchPath: j['searchPath'] as String? ?? 'search',
        detailsPath: j['detailsPath'] as String? ?? '',
        resultsPath: j['resultsPath'] as String? ?? 'results',
        detailsRoot: j['detailsRoot'] as String? ?? '',
        searchQuery: (j['searchQuery'] as Map? ?? {'q': '{query}'})
            .cast<String, String>(),
        fields: (j['fields'] as Map? ?? {'title': 'title'})
            .cast<String, String>(),
        authHeader: j['authHeader'] as String? ?? 'Authorization',
        authPrefix: j['authPrefix'] as String? ?? 'Bearer ',
        allowLan: j['allowLan'] == true,
      );
}

class CustomScraperRepository {
  static const key = 'metadata.custom.profiles';
  Future<List<CustomScraperProfile>> load() async {
    final raw = await NativeBridge.secretRead(key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List)
        .map((j) => CustomScraperProfile.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    for (final p in list) p.validate();
    return list;
  }

  Future<void> save(
    CustomScraperProfile profile, {
    String token = '',
    bool clearToken = false,
  }) async {
    profile.validate();
    if (token.contains(RegExp(r'[\r\n]')) || token.length > 4096)
      throw const FormatException('密钥格式无效');
    final profiles = await load();
    profiles.removeWhere((p) => p.id == profile.id);
    if (profiles.length >= 20) throw const FormatException('最多保存 20 个自定义 API');
    if (clearToken) await NativeBridge.secretDelete(profile.credentialKey);
    if (token.isNotEmpty)
      await NativeBridge.secretWrite(profile.credentialKey, token);
    await NativeBridge.secretWrite(
      key,
      jsonEncode([...profiles.map((p) => p.toJson()), profile.toJson()]),
    );
  }

  Future<void> remove(CustomScraperProfile profile) async {
    final profiles = await load();
    profiles.removeWhere((p) => p.id == profile.id);
    await NativeBridge.secretWrite(
      key,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
    await NativeBridge.secretDelete(profile.credentialKey);
  }

  Future<CustomScraperClient> client(CustomScraperProfile profile) async =>
      CustomScraperClient(
        profile,
        token: await NativeBridge.secretRead(profile.credentialKey) ?? '',
      );
}

class CustomScraperClient {
  CustomScraperClient(
    this.profile, {
    this.token = '',
    MetadataTransport? transport,
  }) : _http = transport ?? MetadataTransport() {
    profile.validate();
  }
  final CustomScraperProfile profile;
  final String token;
  final MetadataTransport _http;
  Map<String, String> get _headers =>
      token.isEmpty ? {} : {profile.authHeader: '${profile.authPrefix}$token'};
  static Object? at(Object? value, String path) {
    if (path.isEmpty) return value;
    for (final segment in path.split('.')) {
      if (value is Map) {
        value = value[segment];
      } else if (value is List &&
          int.tryParse(segment) != null &&
          int.parse(segment) >= 0 &&
          int.parse(segment) < value.length) {
        value = value[int.parse(segment)];
      } else {
        return null;
      }
    }
    return value;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(profile.baseUrl);
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/$path',
      queryParameters: query,
    );
  }

  Future<List<MediaMetadata>> search(
    MediaItem item,
    String query, {
    String language = 'zh-CN',
  }) async {
    if (!profile.kinds.contains(item.kind.name))
      throw const FormatException('此 API 不适用于当前视频类型');
    if (query.trim().isEmpty || query.length > 500)
      throw const FormatException('请输入 1–500 字的查询');
    if (!RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$').hasMatch(language))
      throw const FormatException('资料语言需使用 zh-CN、ja-JP 等语言代码');
    final values = {
      'query': query.trim(),
      'kind': item.kind.name,
      'category': profile.category,
      'language': language,
      'year': '${item.year ?? ''}',
      'season': '${item.season ?? ''}',
      'episode': '${item.episode ?? ''}',
    };
    final params = profile.searchQuery.map(
      (k, v) => MapEntry(
        k,
        v.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) => values[m[1]]!),
      ),
    );
    final response = await _http.json(
      _uri(profile.searchPath, params),
      headers: _headers,
      allowLan: profile.allowLan,
    );
    final results = at(response, profile.resultsPath);
    if (results is! List)
      throw const FormatException('结果路径没有返回 JSON 数组，请检查 resultsPath');
    final parsed = <MediaMetadata>[];
    for (final raw in results.take(80)) {
      if (raw is Map) parsed.add(_parse(raw, item));
    }
    return parsed;
  }

  Future<MediaMetadata> details(MediaMetadata candidate, MediaItem item) async {
    if (profile.detailsPath.isEmpty) return candidate;
    final id = candidate.externalIds['custom_id'] ?? '';
    if (id.isEmpty) throw const FormatException('详情接口需要结果中的 id 映射');
    // ID is a single path segment. Uri.replace performs escaping exactly once.
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(id))
      throw const FormatException('详情 ID 需为字母、数字、下划线或短横线');
    final response = await _http.json(
      _uri(profile.detailsPath.replaceAll('{id}', id)),
      headers: _headers,
      allowLan: profile.allowLan,
    );
    final raw = at(response, profile.detailsRoot);
    if (raw is! Map) throw const FormatException('详情根路径未返回 JSON 对象');
    final result = _parse(raw, item);
    if (result.externalIds['custom_id'] != id)
      throw const FormatException('详情 ID 与所选结果不一致');
    return result;
  }

  MediaMetadata _parse(Map raw, MediaItem item) {
    final j = <String, dynamic>{
      for (final e in profile.fields.entries) e.key: at(raw, e.value),
    };
    if (j['title'] is! String ||
        (j['title'] as String).trim().isEmpty ||
        (j['title'] as String).length > 500)
      throw const FormatException('结果缺少有效标题，请检查字段映射');
    for (final key in [
      'overview',
      'originalTitle',
      'originalLanguage',
      'language',
    ]) {
      if (j[key] != null &&
          (j[key] is! String || (j[key] as String).length > 16000))
        throw const FormatException('结果文字字段无效');
    }
    for (final key in ['genres', 'countries']) {
      if (j[key] != null &&
          (j[key] is! List ||
              (j[key] as List).length > 100 ||
              (j[key] as List).any((v) => v is! String || v.length > 200)))
        throw const FormatException('类型与地区字段需为文字数组');
    }
    for (final key in ['posterUrl', 'backdropUrl']) j[key] = _image(j[key]);
    final people = <MediaPerson>[];
    for (final raw in (j['people'] as List? ?? []).take(100)) {
      if (raw is! Map || raw['name'] is! String || raw['name'].length > 200)
        throw const FormatException('人员列表格式无效');
      people.add(
        MediaPerson(
          name: raw['name'],
          role: '${raw['role'] ?? ''}',
          department: '${raw['department'] ?? ''}',
        ),
      );
    }
    final ratings = <MediaRating>[];
    for (final raw in (j['ratings'] as List? ?? []).take(30)) {
      if (raw is! Map || raw['value'] is! num || raw['source'] is! String)
        throw const FormatException('评分需包含来源和分值');
      final r = MediaRating.fromJson(Map<String, dynamic>.from(raw));
      if (!r.valid || (r.votes != null && r.votes! < 0))
        throw const FormatException('评分值超出其满分尺度');
      ratings.add(r);
    }
    try {
      return MediaMetadata.fromJson({
        ...j,
        'id': 0,
        'provider': 'custom:${profile.id}',
        'reviewed': true,
        'mediaType': item.kind.name,
        'year': int.tryParse('${j['year'] ?? ''}'),
        'people': people.map((p) => p.toJson()).toList(),
        'ratings': ratings.map((r) => r.toJson()).toList(),
        'externalIds': {if (j['id'] != null) 'custom_id': '${j['id']}'},
        'notes': [
          '资料服务：${profile.name}',
          if (profile.category.isNotEmpty) '自定义视频类型：${profile.category}',
        ],
      });
    } catch (_) {
      throw const FormatException('结果的多语言资料或列表格式不符合映射协议');
    }
  }

  String? _image(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String || value.length > 2048)
      throw const FormatException('图片地址无效');
    final uri = Uri.parse(profile.baseUrl).resolve(value);
    if (uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !(uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                uri.origin == Uri.parse(profile.baseUrl).origin)))
      throw const FormatException('图片仅支持 HTTPS 或同源的本机／局域网 HTTP 地址');
    return uri.toString();
  }

  void close() => _http.close();
}
