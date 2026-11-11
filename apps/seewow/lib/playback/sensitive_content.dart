import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/media_metadata.dart';

bool hasSensitiveMetadata(MediaMetadata? metadata) =>
    metadata != null &&
    (metadata.adult == true ||
        metadata.genres.any(
          (g) => const {
            'nsfw',
            'adult',
            'porn',
            'pornography',
            '色情',
            '成人色情',
          }.contains(g.trim().toLowerCase()),
        ));

/// A user-supplied local classifier, never an implicit cloud upload. Only literal
/// loopback addresses are accepted, avoiding DNS rebinding and redirect leaks.
class SensitiveContentClient {
  SensitiveContentClient(String endpoint)
    : endpoint = validateEndpoint(endpoint);
  final Uri endpoint;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2);
  static Uri validateEndpoint(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'http' ||
        !{'127.0.0.1', '::1', '[::1]'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const FormatException(
        '检测接口仅支持本机 http://127.0.0.1:端口/路径 或 IPv6 回环地址',
      );
    }
    return uri;
  }

  Future<bool> detect(Uint8List image) => _detect(image).timeout(
    const Duration(seconds: 8),
    onTimeout: () {
      close();
      throw TimeoutException('本机检测超时');
    },
  );
  Future<bool> _detect(Uint8List image) async {
    if (image.isEmpty || image.length > 512 * 1024)
      throw const FormatException('检测帧大小无效');
    final request = await _http
        .postUrl(endpoint)
        .timeout(const Duration(seconds: 3));
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode({'image_base64': base64Encode(image)})));
    final response = await request.close().timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      close();
      throw const FormatException('本机检测未成功');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 5))) {
      if (bytes.length + chunk.length > 8192) {
        _http.close(force: true);
        throw const FormatException('检测响应过大');
      }
      bytes.addAll(chunk);
    }
    final j = jsonDecode(utf8.decode(bytes));
    if (j is! Map ||
        j['nsfw'] is! bool ||
        j['confidence'] is! num ||
        !(j['confidence'] as num).isFinite ||
        j['confidence'] < 0 ||
        j['confidence'] > 1) {
      throw const FormatException('检测响应需包含 nsfw 布尔值和 0–1 confidence');
    }
    return j['nsfw'] == true && j['confidence'] >= .8;
  }

  void close() => _http.close(force: true);
}
