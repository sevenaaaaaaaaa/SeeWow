import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'remote_hub.dart';

/// LAN remote control for the desktop app.
///
/// Phones discover the host over UDP, pair with a 6-digit code and then send
/// playback commands over local HTTP. Commands are accepted only with a token
/// issued by this server; nothing is exposed beyond the current player.
class RemoteServer {
  RemoteServer({RemoteHub? hub}) : _hub = hub ?? RemoteHub.instance;
  static final RemoteServer instance = RemoteServer();

  final RemoteHub _hub;
  RemoteBridgeHost? bridgeHost;
  String _bridgeKey = '';
  HttpServer? _http;
  RawDatagramSocket? _udp;
  final Map<String, String> _tokens = {};
  String _code = '';
  String _name = 'SeeWow';
  String _id = '';
  int _httpPort = 0;
  int _udpPort = 0;
  final List<DateTime> _pairFailures = [];

  bool get running => _http != null;
  int get httpPort => _httpPort;
  int get udpPort => _udpPort;
  String get pairingCode => _code;
  String get deviceName => _name;
  String get deviceId => _id;
  int get pairedDevices => _tokens.length;

  Future<void> start({
    required String code,
    String name = 'SeeWow',
    int httpPort = 47834,
    int udpPort = 47833,
    String bridgeKey = '',
  }) async {
    if (running) await stop();
    _code = code;
    _bridgeKey = bridgeKey;
    _name = name;
    _id = _randomHex(8);
    _tokens.clear();
    _pairFailures.clear();

    HttpServer? server;
    if (httpPort == 0) {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } else {
      for (var p = httpPort; p < httpPort + 8; p++) {
        try {
          server = await HttpServer.bind(InternetAddress.anyIPv4, p);
          break;
        } catch (_) {}
      }
    }
    if (server == null) {
      throw const SocketException('遥控端口被占用，请关闭占用程序后重试');
    }
    _httpPort = server.port;
    server.listen(_handle, onError: (_) {});
    _http = server;

    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
    } catch (_) {
      // Discovery is optional; manual address entry still works.
      try {
        _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (_) {
        _udp = null;
      }
    }
    final udp = _udp;
    if (udp != null) {
      _udpPort = udp.port;
      udp.broadcastEnabled = true;
      udp.listen(_onDatagram);
    }
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _http = null;
    _udp?.close();
    _udp = null;
    _tokens.clear();
  }

  void rotateCode(String code) {
    _code = code;
    _tokens.clear();
    _pairFailures.clear();
  }

  Future<List<String>> addresses() async {
    final result = <String>[];
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          result.add(address.address);
        }
      }
    } catch (_) {}
    return result;
  }

  void _onDatagram(RawSocketEvent event) {
    final udp = _udp;
    if (udp == null || event != RawSocketEvent.read) return;
    final datagram = udp.receive();
    if (datagram == null || datagram.data.length > 256) return;
    final text = utf8.decode(datagram.data, allowMalformed: true).trim();
    if (text != 'SEEWOW1 DISCOVER') return;
    final offer = jsonEncode({'name': _name, 'port': _httpPort, 'id': _id});
    try {
      udp.send(
        utf8.encode('SEEWOW1 ' + offer),
        datagram.address,
        datagram.port,
      );
    } catch (_) {}
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    try {
      if (request.method == 'POST' && request.uri.path == '/api/pair') {
        await _pair(request, response);
      } else if (request.uri.path == '/api/status' && request.method == 'GET') {
        final token = _token(request);
        if (token == null) {
          response.statusCode = HttpStatus.unauthorized;
          response.write(jsonEncode({'error': '未配对'}));
        } else {
          response.write(jsonEncode(_status()));
        }
      } else if (request.uri.path == '/api/library' &&
          request.method == 'GET') {
        final token = _token(request);
        if (token == null) {
          response.statusCode = HttpStatus.unauthorized;
          response.write(jsonEncode({'error': '未配对'}));
        } else {
          await _library(request, response);
        }
      } else if (request.uri.path == '/api/open' && request.method == 'POST') {
        final token = _token(request);
        if (token == null) {
          response.statusCode = HttpStatus.unauthorized;
          response.write(jsonEncode({'error': '未配对'}));
        } else {
          await _open(request, response);
        }
      } else if (request.uri.path == '/api/command' &&
          request.method == 'POST') {
        final token = _token(request);
        if (token == null) {
          response.statusCode = HttpStatus.unauthorized;
          response.write(jsonEncode({'error': '未配对'}));
        } else {
          await _command(request, response);
        }
      } else if (request.uri.path == '/bridge/library' &&
          request.method == 'GET') {
        if (_token(request) == null) {
          response.statusCode = HttpStatus.unauthorized;
          response.write(jsonEncode({'error': '未配对'}));
        } else {
          await _bridgeLibrary(request, response);
        }
      } else if (request.uri.path == '/bridge/stream') {
        await _bridgeStream(request, response);
      } else if (request.uri.path == '/bridge/poster') {
        await _bridgePoster(request, response);
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write(jsonEncode({'error': '未知接口'}));
      }
    } catch (error) {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'error': error.toString()}));
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  String? _token(HttpRequest request) {
    final token = request.headers.value('X-SeeWow-Token');
    return token != null && _tokens.containsKey(token) ? token : null;
  }

  Future<void> _library(HttpRequest request, HttpResponse response) async {
    final host = _hub.library;
    if (host == null) {
      response.write(jsonEncode({'items': <Object>[], 'total': 0}));
      return;
    }
    final query = (request.uri.queryParameters['q'] ?? '').trim().toLowerCase();
    final limit =
        (int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 100).clamp(
          1,
          100,
        );
    var items = await host.remoteItems();
    if (query.isNotEmpty) {
      items = items
          .where((item) => item.title.toLowerCase().contains(query))
          .toList();
    }
    response.write(
      jsonEncode({
        'total': items.length,
        'items': items.take(limit).map((item) => item.toJson()).toList(),
      }),
    );
  }

  Future<void> _open(HttpRequest request, HttpResponse response) async {
    final payload = await _jsonBody(request);
    final id = payload['id']?.toString() ?? '';
    final host = _hub.library;
    if (host == null) {
      response.statusCode = HttpStatus.conflict;
      response.write(jsonEncode({'error': '桌面片库尚未就绪'}));
      return;
    }
    if (id.isEmpty || !await host.remoteOpen(id)) {
      response.statusCode = HttpStatus.notFound;
      response.write(jsonEncode({'error': '片库中找不到该影片'}));
      return;
    }
    response.write(jsonEncode(_status()));
  }

  Future<void> _pair(HttpRequest request, HttpResponse response) async {
    final now = DateTime.now();
    _pairFailures.removeWhere(
      (at) => now.difference(at) > const Duration(seconds: 30),
    );
    if (_pairFailures.length >= 5) {
      response.statusCode = HttpStatus.tooManyRequests;
      response.write(jsonEncode({'error': '尝试过多，请稍后再试'}));
      return;
    }
    final payload = await _jsonBody(request);
    final code = payload['code']?.toString() ?? '';
    if (code != _code) {
      _pairFailures.add(now);
      response.statusCode = HttpStatus.unauthorized;
      response.write(jsonEncode({'error': '验证码不正确'}));
      return;
    }
    _pairFailures.clear();
    final token = _randomHex(24);
    _tokens[token] = payload['device']?.toString() ?? '手机';
    response.write(
      jsonEncode({
        'token': token,
        'name': _name,
        if (_bridgeKey.isNotEmpty) 'bridgeKey': _bridgeKey,
      }),
    );
  }

  Future<void> _command(HttpRequest request, HttpResponse response) async {
    final payload = await _jsonBody(request);
    final action = payload['action']?.toString() ?? '';
    final value = payload['value'];
    final playback = _hub.active;
    if (playback == null) {
      response.statusCode = HttpStatus.conflict;
      response.write(jsonEncode({'error': '桌面没有正在播放的影片'}));
      return;
    }
    switch (action) {
      case 'toggle':
        await playback.remoteToggle();
        break;
      case 'seek':
        final seconds = (value as num?)?.toDouble() ?? 0;
        final total = playback.remoteDuration;
        var target = Duration(milliseconds: (seconds * 1000).round());
        if (target < Duration.zero) target = Duration.zero;
        if (total > Duration.zero && target > total) target = total;
        await playback.remoteSeek(target);
        break;
      case 'volume':
        final volume = ((value as num?)?.toDouble() ?? 0).clamp(0, 100);
        await playback.remoteSetVolume(volume.toDouble());
        break;
      case 'seekRelative':
        final delta = ((value as num?)?.toDouble() ?? 0) * 1000;
        final total = playback.remoteDuration;
        var target =
            playback.remotePosition + Duration(milliseconds: delta.round());
        if (target < Duration.zero) target = Duration.zero;
        if (total > Duration.zero && target > total) target = total;
        await playback.remoteSeek(target);
        break;
      default:
        response.statusCode = HttpStatus.badRequest;
        response.write(jsonEncode({'error': '不支持的操作'}));
        return;
    }
    response.write(jsonEncode(_status()));
  }

  bool _validBridgeKey(String key) {
    if (_bridgeKey.isEmpty || key.isEmpty || key.length != _bridgeKey.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < key.length; i++) {
      diff |= key.codeUnitAt(i) ^ _bridgeKey.codeUnitAt(i);
    }
    return diff == 0;
  }

  String _baseUrl(HttpRequest request) {
    final host = request.headers.value(HttpHeaders.hostHeader);
    if (host != null && host.isNotEmpty) return 'http://$host';
    return 'http://127.0.0.1:$_httpPort';
  }

  Future<void> _bridgeLibrary(
    HttpRequest request,
    HttpResponse response,
  ) async {
    final bridge = bridgeHost;
    if (bridge == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      response.write(jsonEncode({'error': '局域网代理尚未就绪'}));
      return;
    }
    final base = _baseUrl(request);
    final items = <Map<String, Object?>>[];
    for (final item in bridge.bridgeItems.take(5000)) {
      final id = Uri.encodeQueryComponent(item.id);
      final poster = item.posterUrl ?? item.backdropUrl;
      items.add({
        'id': item.id,
        'title': item.displayTitle,
        'showTitle': item.showTitle,
        'season': item.season,
        'episode': item.episode,
        'year': item.year,
        'kind': item.kind.name,
        'duration': item.duration,
        'fileSize': item.fileSize,
        'quality': item.quality,
        'stream': '$base/bridge/stream?id=$id&key=$_bridgeKey',
        if (poster != null && poster.isNotEmpty)
          'poster': '$base/bridge/poster?id=$id&key=$_bridgeKey',
      });
    }
    response.write(jsonEncode({'items': items, 'total': items.length}));
  }

  Future<void> _bridgeStream(HttpRequest request, HttpResponse response) async {
    if (!_validBridgeKey(request.uri.queryParameters['key'] ?? '')) {
      response.statusCode = HttpStatus.forbidden;
      response.write(jsonEncode({'error': '代理密钥无效'}));
      return;
    }
    final bridge = bridgeHost;
    if (bridge == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    final id = request.uri.queryParameters['id'] ?? '';
    final item = await bridge.bridgeItem(id);
    if (item == null) {
      response.statusCode = HttpStatus.notFound;
      response.write(jsonEncode({'error': '条目不存在'}));
      return;
    }
    final prepared = await bridge.bridgePrepare(item);
    final uri = Uri.tryParse(prepared.locator);
    File? file;
    if (uri != null && uri.scheme == 'file') {
      file = File.fromUri(uri);
    } else if (uri == null || uri.scheme.isEmpty) {
      file = File(prepared.locator);
    }
    if (file != null) {
      await _serveFile(file, request, response, prepared.container);
      return;
    }
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await _proxyRemote(uri, prepared.httpHeaders, request, response);
      return;
    }
    response.statusCode = HttpStatus.unsupportedMediaType;
    response.write(jsonEncode({'error': '该条目无法通过局域网代理播放'}));
  }

  Future<void> _bridgePoster(HttpRequest request, HttpResponse response) async {
    if (!_validBridgeKey(request.uri.queryParameters['key'] ?? '')) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    final bridge = bridgeHost;
    if (bridge == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    final id = request.uri.queryParameters['id'] ?? '';
    final item = await bridge.bridgeItem(id);
    if (item == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final prepared = await bridge.bridgePrepare(item);
    final poster = prepared.posterUrl ?? prepared.backdropUrl;
    if (poster == null || poster.isEmpty) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final uri = Uri.tryParse(poster);
    final file = uri != null && uri.scheme == 'file'
        ? File.fromUri(uri)
        : (uri == null || uri.scheme.isEmpty)
        ? File(poster)
        : null;
    if (file != null) {
      final ext = poster.split('.').last.toLowerCase();
      await _serveFile(file, request, response, ext);
      return;
    }
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await _proxyRemote(uri, prepared.httpHeaders, request, response);
      return;
    }
    response.statusCode = HttpStatus.notFound;
  }

  Future<void> _serveFile(
    File file,
    HttpRequest request,
    HttpResponse response,
    String container,
  ) async {
    if (!await file.exists()) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final total = await file.length();
    var start = 0;
    var end = total - 1;
    var partial = false;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final spec = range.substring(6).split(',').first.trim();
      final parts = spec.split('-');
      final first = int.tryParse(parts.first);
      if (first != null) {
        start = first;
        final second = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (second != null) end = second;
        partial = true;
      } else if (parts.length > 1) {
        final suffix = int.tryParse(parts[1]);
        if (suffix != null) {
          start = (total - suffix).clamp(0, total);
          partial = true;
        }
      }
      if (start >= total) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        return;
      }
      end = end.clamp(start, total - 1);
    }
    final length = end - start + 1;
    response.headers.contentType = _contentType(container, file.path);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (partial) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }
    response.headers.contentLength = length;
    if (request.method == 'HEAD') return;
    await response.addStream(file.openRead(start, end + 1));
  }

  Future<void> _proxyRemote(
    Uri uri,
    Map<String, String> headers,
    HttpRequest request,
    HttpResponse response,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final outbound = await client.getUrl(uri);
      headers.forEach(outbound.headers.set);
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
    } finally {
      client.close(force: true);
    }
  }

  ContentType _contentType(String container, String path) {
    var ext = container.replaceAll('.', '').toLowerCase();
    if (ext.isEmpty) {
      final parts = path.split('.');
      ext = parts.length > 1 ? parts.last.toLowerCase() : '';
    }
    if (ext == 'mp4' || ext == 'm4v') return ContentType('video', 'mp4');
    if (ext == 'mkv') return ContentType('video', 'x-matroska');
    if (ext == 'webm') return ContentType('video', 'webm');
    if (ext == 'ts') return ContentType('video', 'mp2t');
    if (ext == 'mp3') return ContentType('audio', 'mpeg');
    if (ext == 'm4a') return ContentType('audio', 'mp4');
    if (ext == 'flac') return ContentType('audio', 'flac');
    if (ext == 'jpg' || ext == 'jpeg') return ContentType('image', 'jpeg');
    if (ext == 'png') return ContentType('image', 'png');
    if (ext == 'webp') return ContentType('image', 'webp');
    return ContentType.binary;
  }

  Map<String, Object?> _status() {
    final playback = _hub.active;
    return {
      'hasPlayback': playback != null,
      'title': playback?.remoteTitle ?? '',
      'position': playback?.remotePosition.inMilliseconds ?? 0,
      'duration': playback?.remoteDuration.inMilliseconds ?? 0,
      'playing': playback?.remotePlaying ?? false,
      'volume': playback?.remoteVolume ?? 0,
    };
  }

  Future<Map<String, dynamic>> _jsonBody(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > 8192) throw const FormatException('请求过大');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('请求格式无效');
    }
    return decoded;
  }

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return List<String>.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
