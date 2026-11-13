import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persisted switch, port and pairing code for the LAN remote control.
class RemoteSettings extends ChangeNotifier {
  RemoteSettings({this.directory});
  static final RemoteSettings instance = RemoteSettings._();
  RemoteSettings._();

  Directory? directory;
  bool enabled = false;
  int port = 47834;
  String code = '';
  String bridgeKey = '';

  Future<File> _file() async {
    final dir =
        directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/SeeWow');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/remote.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      enabled = raw['enabled'] == true;
      port = (raw['port'] as num?)?.toInt() ?? 47834;
      code = raw['code']?.toString() ?? '';
      bridgeKey = raw['bridgeKey']?.toString() ?? '';
    } catch (_) {
      // A damaged file simply starts with remote control disabled.
    }
    if (code.length != 6) code = newCode();
    if (bridgeKey.length < 32) bridgeKey = newBridgeKey();
  }

  Future<void> save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'enabled': enabled,
          'port': port,
          'code': code,
          'bridgeKey': bridgeKey,
        }),
      );
    } catch (_) {}
    notifyListeners();
  }

  String newCode() => (Random.secure().nextInt(900000) + 100000).toString();

  String newBridgeKey() => List.generate(
    32,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();

  String rotateBridgeKey() {
    bridgeKey = newBridgeKey();
    return bridgeKey;
  }

  String rotateCode() {
    code = newCode();
    return code;
  }
}
