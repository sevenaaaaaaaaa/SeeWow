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
  }) async {
    if (running) await stop();
    _code = code;
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
    response.write(jsonEncode({'token': token, 'name': _name}));
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
