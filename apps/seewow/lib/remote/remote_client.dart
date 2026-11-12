import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RemoteDevice {
  const RemoteDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.id,
  });
  final String name, host, id;
  final int port;
  String get label => '$name · $host:$port';
}

class RemoteStatus {
  const RemoteStatus({
    required this.hasPlayback,
    required this.title,
    required this.position,
    required this.duration,
    required this.playing,
    required this.volume,
  });
  final bool hasPlayback, playing;
  final String title;
  final Duration position, duration;
  final double volume;

  factory RemoteStatus.fromJson(Map<String, dynamic> json) => RemoteStatus(
    hasPlayback: json['hasPlayback'] == true,
    title: json['title']?.toString() ?? '',
    position: Duration(milliseconds: (json['position'] as num? ?? 0).toInt()),
    duration: Duration(milliseconds: (json['duration'] as num? ?? 0).toInt()),
    playing: json['playing'] == true,
    volume: (json['volume'] as num? ?? 0).toDouble(),
  );
}

class RemoteException implements Exception {
  RemoteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Phone side of the LAN remote. Discovery is best-effort UDP broadcast; a
/// manual host and port always works when the LAN blocks broadcasts.
class RemoteClient {
  RemoteClient({HttpClient Function()? clientFactory})
    : _factory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _factory;
  String host = '';
  int port = 47834;
  String? _token;
  HttpClient? _client;

  bool get paired => _token != null;

  Future<List<RemoteDevice>> discover({
    Duration timeout = const Duration(seconds: 2),
    int discoveryPort = 47833,
  }) async {
    final found = <String, RemoteDevice>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null || datagram.data.length > 512) return;
        final text = utf8.decode(datagram.data, allowMalformed: true).trim();
        if (!text.startsWith('SEEWOW1 ')) return;
        try {
          final offer = jsonDecode(
            text.substring('SEEWOW1 '.length),
          ) as Map<String, dynamic>;
          final devicePort = (offer['port'] as num?)?.toInt() ?? 0;
          final id = offer['id']?.toString() ?? '';
          if (devicePort <= 0 || id.isEmpty) return;
          found[id] = RemoteDevice(
            name: offer['name']?.toString() ?? 'SeeWow 电脑',
            host: datagram.address.address,
            port: devicePort,
            id: id,
          );
        } catch (_) {}
      });
      final payload = utf8.encode('SEEWOW1 DISCOVER');
      for (final address in [
        InternetAddress('255.255.255.255'),
        InternetAddress.loopbackIPv4,
      ]) {
        try {
          socket.send(payload, address, discoveryPort);
        } catch (_) {}
      }
      await Future<void>.delayed(timeout);
    } catch (_) {
      // Manual connection remains available.
    } finally {
      socket?.close();
    }
    return found.values.toList();
  }

  void configure(String host, int port) {
    this.host = host.trim();
    this.port = port;
    _token = null;
    _client?.close(force: true);
    _client = _factory()..connectionTimeout = const Duration(seconds: 5);
  }

  Future<void> pair(String code, {String device = '手机'}) async {
    final json = await _post('/api/pair', {
      'code': code.trim(),
      'device': device,
    });
    final token = json['token']?.toString() ?? '';
    if (token.isEmpty) throw RemoteException('配对失败');
    _token = token;
  }

  Future<RemoteStatus> status() async {
    final json = await _get('/api/status');
    return RemoteStatus.fromJson(json);
  }

  Future<RemoteStatus> command(String action, [num? value]) async {
    final json = await _post('/api/command', {
      'action': action,
      if (value != null) 'value': value,
    });
    return RemoteStatus.fromJson(json);
  }

  Future<Map<String, dynamic>> _get(String path) => _request('GET', path);

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body) =>
      _request('POST', path, body: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final client = _client ??= _factory()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://$host:$port$path'),
      );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final token = _token;
      if (token != null) request.headers.set('X-SeeWow-Token', token);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) throw RemoteException('响应过大');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw RemoteException('响应格式无效');
      }
      if (response.statusCode == 401) {
        _token = null;
        throw RemoteException(decoded['error']?.toString() ?? '配对已失效');
      }
      if (response.statusCode >= 400) {
        throw RemoteException(decoded['error']?.toString() ?? '遥控请求失败');
      }
      return decoded;
    } on RemoteException {
      rethrow;
    } on TimeoutException {
      throw RemoteException('连接超时，确认电脑和手机在同一 Wi-Fi');
    } on SocketException {
      throw RemoteException('无法连接电脑，检查地址、端口和防火墙');
    } catch (_) {
      throw RemoteException('遥控连接失败');
    }
  }

  void close() {
    _client?.close(force: true);
    _client = null;
    _token = null;
  }
}
