import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SubscriptionText {
  const SubscriptionText(this.text, this.uri);
  final String text;
  final Uri uri;
}

/// Reads data only. Redirects never expand access to local files or networks.
class SubscriptionReader {
  const SubscriptionReader({
    this.maxBytes = 8 * 1024 * 1024,
    this.timeout = const Duration(seconds: 25),
    this.securityContext,
  });
  final int maxBytes;
  final Duration timeout;
  final SecurityContext? securityContext;

  Future<SubscriptionText> read(
    String source, {
    bool allowLocalNetwork = false,
  }) async {
    final uri = Uri.tryParse(source.trim());
    if (uri == null) throw const FormatException('地址格式无效');
    if (!uri.hasScheme ||
        uri.scheme == 'file' ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(source.trim())) {
      final file = uri.scheme == 'file'
          ? File.fromUri(uri)
          : File(source.trim());
      if (await file.length() > maxBytes)
        throw const FormatException('文件超过读取大小限制');
      return SubscriptionText(
        await _decode(file.openRead()).timeout(timeout),
        file.absolute.uri,
      );
    }
    final client = HttpClient()..autoUncompress = true;
    client.connectionTimeout = timeout;
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (target, _, _) async {
      final addresses = await InternetAddress.lookup(target.host);
      if (addresses.isEmpty ||
          (!allowLocalNetwork && addresses.any(isLocalAddress))) {
        throw const FormatException('此地址访问局域网；仅在信任该订阅时开启局域网访问');
      }
      // Lookup results retain the original hostname for SNI/certificate checks.
      // Passing that InternetAddress pins the checked IP without another lookup.
      return target.scheme == 'https'
          ? SecureSocket.startConnect(
              addresses.first,
              target.port,
              context: securityContext,
            )
          : Socket.startConnect(addresses.first, target.port);
    };
    Future<SubscriptionText> fetch() async {
      var current = uri;
      for (var redirects = 0; redirects <= 4; redirects++) {
        validateWebUri(current);
        final request = await client.getUrl(current);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'SeeWow/1.6');
        final response = await request.close();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw const FormatException('重定向缺少地址');
          final next = current.resolve(location);
          if (current.scheme == 'https' && next.scheme != 'https') {
            throw const FormatException('不允许 HTTPS 降级重定向');
          }
          current = next;
          // Do not consume an unbounded redirect body.
          await response.listen((_) {}).cancel();
          continue;
        }
        if (response.statusCode != 200) {
          throw FormatException('服务返回 HTTP ${response.statusCode}');
        }
        if (response.contentLength > maxBytes)
          throw const FormatException('文件超过读取大小限制');
        return SubscriptionText(await _decode(response), current);
      }
      throw const FormatException('重定向次数过多');
    }

    try {
      return await fetch().timeout(timeout);
    } on TimeoutException {
      throw const FormatException('读取超时，请稍后重试');
    } on SocketException {
      throw const FormatException('无法连接订阅，请检查网络和地址');
    } on HandshakeException {
      throw const FormatException('无法验证订阅的安全连接');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _decode(Stream<List<int>> stream) async {
    var total = 0;
    final bounded = stream.map((chunk) {
      total += chunk.length;
      if (total > maxBytes) throw const FormatException('文件超过读取大小限制');
      return chunk;
    });
    return utf8.decoder.bind(bounded).join();
  }

  static void validateWebUri(Uri uri) {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('仅支持不含内嵌账号密码的 HTTP(S) 地址');
    }
  }

  static bool isLocalAddress(InternetAddress address) {
    final b = address.rawAddress;
    if (b.length == 4) {
      return b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    if (b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255) {
      return isLocalAddress(InternetAddress.fromRawAddress(b.sublist(12)));
    }
    // Only global-unicast IPv6 is accepted without explicit LAN permission.
    return (b[0] & 0xe0) != 0x20;
  }
}
