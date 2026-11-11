import 'dart:convert';
import 'dart:io';

/// Bounded transport: no redirects with credentials and no raw URLs in errors.
class JsonApi {
  JsonApi(
    this.base, {
    this.headers = const {},
    this.maxBytes = 16 * 1024 * 1024,
  }) {
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment)
      throw const FormatException('请填写不含账号、密钥或查询参数的服务地址');
  }
  final Uri base;
  final Map<String, String> headers;
  final int maxBytes;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  Uri uri(String path, [Map<String, String> query = const {}]) => base.replace(
    path:
        '${base.path.replaceAll(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}',
    queryParameters: query.isEmpty ? null : query,
  );
  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String> query = const {},
  ]) => _request('GET', path, query: query);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: jsonEncode(body));
  Future<Map<String, dynamic>> form(String path, Map<String, String> body) =>
      _request(
        'POST',
        path,
        body: Uri(queryParameters: body).query,
        form: true,
      );
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String> query = const {},
    String? body,
    bool form = false,
  }) async {
    try {
      final req = await _client.openUrl(method, uri(path, query));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentType = form
            ? ContentType(
                'application',
                'x-www-form-urlencoded',
                charset: 'utf-8',
              )
            : ContentType.json;
        req.write(body);
      }
      final response = await req.close().timeout(const Duration(seconds: 25));
      if (response.statusCode != 200)
        throw HttpException(switch (response.statusCode) {
          401 || 403 => '认证失败（HTTP ${response.statusCode}），请检查凭据与访问权限',
          404 => '接口不存在（HTTP 404），请检查服务根路径',
          429 => '请求过于频繁（HTTP 429），请稍后重试',
          _ => '服务返回 HTTP ${response.statusCode}',
        });
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) throw const FormatException('服务响应超过大小限制');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>)
        throw const FormatException('服务没有返回有效的 JSON 对象');
      return decoded;
    } on HttpException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const HttpException('服务连接失败或超时，请检查地址和网络');
    }
  }

  void close() => _client.close(force: true);
}
