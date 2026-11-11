import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../sources/subscription_reader.dart';

class MetadataCancelled implements Exception {}

/// User-configured metadata/image services, with bounded requests and no redirects.
class MetadataTransport {
  MetadataTransport({this.timeout = const Duration(seconds: 30)});
  final Duration timeout;
  HttpClient? _active;
  int _revision = 0;

  static Uri endpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment)
      throw const FormatException('服务地址需为不含账号、查询参数或片段的 HTTP(S) 地址');
    return uri;
  }

  void close() {
    _revision++;
    _active?.close(force: true);
    _active = null;
  }

  Future<Object?> json(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
    bool allowLan = false,
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    final ticket = _revision;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    client.findProxy = (_) => 'DIRECT';
    _active = client;
    client.connectionFactory = (target, _, _) async {
      final addresses = await InternetAddress.lookup(target.host);
      if (addresses.isEmpty ||
          addresses.any(
            (a) =>
                (!a.isLoopback &&
                    !allowLan &&
                    SubscriptionReader.isLocalAddress(a)) ||
                (target.scheme == 'http' &&
                    !SubscriptionReader.isLocalAddress(a)),
          ))
        throw const FormatException('公网服务须使用 HTTPS；局域网服务需在配置中明确允许');
      return target.scheme == 'https'
          ? SecureSocket.startConnect(addresses.first, target.port)
          : Socket.startConnect(addresses.first, target.port);
    };
    try {
      final result = await (() async {
        final request = await client.openUrl(
          body == null ? 'GET' : 'POST',
          uri,
        );
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        headers.forEach(request.headers.set);
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        if (response.statusCode != 200)
          throw FormatException('服务返回 HTTP ${response.statusCode}；请检查接口、授权或额度');
        if (response.contentLength > maxBytes)
          throw const FormatException('响应超过大小限制');
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > maxBytes) throw const FormatException('响应超过大小限制');
        }
        return jsonDecode(utf8.decode(bytes));
      })().timeout(timeout);
      if (ticket != _revision) throw MetadataCancelled();
      return result;
    } catch (e) {
      if (ticket != _revision) throw MetadataCancelled();
      if (e is FormatException && e.source == null) rethrow;
      throw const FormatException('服务连接、超时或 JSON 格式失败，请检查配置');
    } finally {
      client.close(force: true);
      if (identical(_active, client)) _active = null;
    }
  }
}
