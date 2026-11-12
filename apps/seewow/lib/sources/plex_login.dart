import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// One Plex account, without asking the user to copy a token by hand.
///
/// The official flow is a PIN: the app creates a short code, the user enters it
/// at https://plex.tv/link, and the app polls until Plex returns an account
/// token. The token is then used to enumerate the account's servers and pick
/// the best reachable connection.
class PlexLogin {
  PlexLogin({
    Uri? endpoint,
    String clientId = '',
    HttpClient Function()? clientFactory,
  }) : endpoint = endpoint ?? Uri.parse('https://plex.tv'),
       clientId = clientId,
       _clientFactory = clientFactory ?? HttpClient.new;

  final Uri endpoint;
  final String clientId;
  final HttpClient Function() _clientFactory;
  static const _product = 'SeeWow';
  static const _version = '1.7.1';

  static Future<PlexLogin> create() async =>
      PlexLogin(clientId: await loadOrCreateClientId());

  static Future<String> loadOrCreateClientId() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/SeeWow');
    final file = File('${dir.path}/plex-client-id');
    try {
      if (await file.exists()) {
        final saved = (await file.readAsString()).trim();
        if (saved.length >= 8 && saved.length <= 128) return saved;
      }
    } catch (_) {
      // A damaged id is replaced; Plex only needs it to be stable per install.
    }
    final random = Random.secure();
    final id = base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      await file.writeAsString(id, flush: true);
    } catch (_) {
      // A read-only support directory should not block account login.
    }
    return id;
  }

  Future<PlexPin> createPin() async {
    // The 4-character code is what plex.tv/link asks for; strong PINs are a
    // 32-character token meant for QR links and are hard to type by hand.
    final json = await _request('POST', '/api/v2/pins');
    final id = (json['id'] as num?)?.toInt();
    final code = json['code']?.toString() ?? '';
    if (id == null || id <= 0 || code.isEmpty)
      throw const PlexException('Plex 没有返回有效的登录验证码');
    return PlexPin(id: id, code: code);
  }

  Future<String?> pollToken(int id) async {
    final json = await _request('GET', '/api/v2/pins/$id');
    final token = json['authToken']?.toString() ?? '';
    return token.isEmpty ? null : token;
  }

  Future<List<PlexServer>> servers(String token) async {
    final json = await _request(
      'GET',
      '/api/v2/resources?includeHttps=1&includeRelay=1',
      token: token,
    );
    if (json is! List) throw const PlexException('Plex 服务器列表格式无效');
    return parseServers(json, token);
  }

  /// Keeps only resources that actually provide a Plex server and have at
  /// least one usable connection. Owned, LAN and non-relay links rank first.
  static List<PlexServer> parseServers(dynamic raw, String accountToken) {
    if (raw is! List) throw const PlexException('Plex 服务器列表格式无效');
    final servers = <PlexServer>[];
    for (final entry in raw.whereType<Map>()) {
      final provides = entry['provides']?.toString() ?? '';
      if (!provides.split(',').map((s) => s.trim()).contains('server'))
        continue;
      final connections = (entry['connections'] as List? ?? [])
          .whereType<Map>()
          .toList();
      final uri = pickConnection(connections);
      if (uri == null) continue;
      final access = entry['accessToken']?.toString() ?? '';
      servers.add(
        PlexServer(
          name: entry['name']?.toString() ?? 'Plex 服务器',
          clientIdentifier: entry['clientIdentifier']?.toString() ?? '',
          uri: uri,
          token: access.isEmpty ? accountToken : access,
          owned: entry['owned'] == true,
        ),
      );
    }
    servers.sort((a, b) {
      if (a.owned != b.owned) return a.owned ? -1 : 1;
      final aLocal = a.uri.contains('plex.direct') ? 1 : 0;
      final bLocal = b.uri.contains('plex.direct') ? 1 : 0;
      return aLocal.compareTo(bLocal);
    });
    return servers;
  }

  static String? pickConnection(List<Map> connections) {
    final usable = connections.where((c) {
      final uri = c['uri'];
      if (uri is! String) return false;
      final parsed = Uri.tryParse(uri);
      return parsed != null &&
          ['http', 'https'].contains(parsed.scheme) &&
          parsed.host.isNotEmpty &&
          parsed.userInfo.isEmpty;
    }).toList();
    String? pick(bool Function(Map) test) {
      for (final connection in usable) {
        if (test(connection)) return connection['uri'] as String;
      }
      return null;
    }

    return pick((c) => c['local'] == true && c['relay'] != true) ??
        pick(
          (c) => c['relay'] != true && (c['uri'] as String).startsWith('https'),
        ) ??
        pick((c) => c['relay'] != true) ??
        pick((_) => true);
  }

  Future<dynamic> _request(String method, String path, {String? token}) async {
    final target = Uri.parse(path);
    final uri = endpoint.replace(
      path: endpoint.path.replaceAll(RegExp(r'/+$'), '') + target.path,
      query: target.query.isEmpty ? null : target.query,
    );
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('X-Plex-Product', _product);
      request.headers.set('X-Plex-Client-Identifier', clientId);
      request.headers.set('X-Plex-Version', _version);
      request.headers.set('X-Plex-Platform', Platform.operatingSystem);
      if (token != null && token.isNotEmpty)
        request.headers.set('X-Plex-Token', token);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024)
          throw const PlexException('Plex 响应超过大小限制');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PlexException(
          response.statusCode == 401 || response.statusCode == 403
              ? 'Plex 登录已失效，请重新登录'
              : 'Plex 服务返回 HTTP ${response.statusCode}',
        );
      }
      return jsonDecode(utf8.decode(bytes));
    } on PlexException {
      rethrow;
    } on TimeoutException {
      throw const PlexException('Plex 连接超时，请检查网络后重试');
    } catch (_) {
      throw const PlexException('无法连接 plex.tv，请检查网络或代理设置');
    } finally {
      client.close(force: true);
    }
  }
}

class PlexPin {
  const PlexPin({required this.id, required this.code});
  final int id;
  final String code;
}

class PlexServer {
  const PlexServer({
    required this.name,
    required this.clientIdentifier,
    required this.uri,
    required this.token,
    required this.owned,
  });
  final String name, clientIdentifier, uri, token;
  final bool owned;

  String get label =>
      clientIdentifier.isEmpty ? name : '$name · $clientIdentifier';
}

class PlexException implements Exception {
  const PlexException(this.message);
  final String message;
  @override
  String toString() => message;
}
