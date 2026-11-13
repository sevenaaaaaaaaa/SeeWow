import 'dart:io';

/// Loopback HTTP proxy used for iOS picture-in-picture.
///
/// AVKit cannot attach custom headers to an asset. The app proxies the
/// authenticated stream through 127.0.0.1, so the PiP player sees a plain URL
/// while the proxy adds provider tokens on the way out.
class LocalStreamProxy {
  LocalStreamProxy._();
  static final LocalStreamProxy instance = LocalStreamProxy._();

  HttpServer? _server;
  Future<HttpServer>? _starting;
  int _counter = 0;
  final Map<String, ({Uri uri, Map<String, String> headers})> _routes = {};

  Future<String> urlFor(Uri uri, Map<String, String> headers) async {
    final server = await (_starting ??= _start());
    final token = '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
    _routes[token] = (uri: uri, headers: Map.unmodifiable(headers));
    return 'http://127.0.0.1:${server.port}/s/$token';
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    _server = server;
    return server;
  }

  void clear() {
    _routes.clear();
  }

  Future<void> close() async {
    _routes.clear();
    await _server?.close(force: true);
    _server = null;
    _starting = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    final route = segments.length == 2 && segments.first == 's'
        ? _routes[segments[1]]
        : null;
    if (route == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final outbound = await client.getUrl(route.uri);
      route.headers.forEach(outbound.headers.set);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) outbound.headers.set(HttpHeaders.rangeHeader, range);
      final upstream = await outbound.close();
      response.statusCode = upstream.statusCode;
      for (final name in const [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
        'last-modified',
      ]) {
        final value = upstream.headers.value(name);
        if (value != null) response.headers.set(name, value);
      }
      if (request.method != 'HEAD') await response.addStream(upstream);
    } catch (_) {
      response.statusCode = HttpStatus.badGateway;
    } finally {
      client.close(force: true);
      try {
        await response.close();
      } catch (_) {}
    }
  }
}
