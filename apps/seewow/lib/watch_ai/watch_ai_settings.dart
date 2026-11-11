import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../sources/native_bridge.dart';

class WatchAiConfig {
  const WatchAiConfig({
    this.enabled = false,
    this.subtitles = true,
    this.companion = true,
    this.allowFrames = false,
    this.endpoint = '',
    this.model = '',
    this.language = '简体中文',
  });
  final bool enabled, subtitles, companion, allowFrames;
  final String endpoint, model, language;
  bool get configured => endpoint.isNotEmpty && model.isNotEmpty;
  String get host => Uri.tryParse(endpoint)?.host ?? '';
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'subtitles': subtitles,
    'companion': companion,
    'allowFrames': allowFrames,
    'endpoint': endpoint,
    'model': model,
    'language': language,
  };
  factory WatchAiConfig.fromJson(Map<String, dynamic> j) => WatchAiConfig(
    enabled: j['enabled'] == true,
    subtitles: j['subtitles'] != false,
    companion: j['companion'] != false,
    allowFrames: j['allowFrames'] == true,
    endpoint: j['endpoint'] as String? ?? '',
    model: j['model'] as String? ?? '',
    language: j['language'] as String? ?? '简体中文',
  );
  void validate() {
    if (endpoint.isNotEmpty) {
      final u = Uri.tryParse(endpoint);
      if (u == null ||
          !['http', 'https'].contains(u.scheme) ||
          u.host.isEmpty ||
          u.userInfo.isNotEmpty ||
          u.hasQuery ||
          u.hasFragment) {
        throw const FormatException(
          '请输入完整的 http(s) Chat Completions 地址，不含密钥或查询参数',
        );
      }
    }
    if (enabled && !configured)
      throw const FormatException('开启前请填写 API 地址和模型名称');
    if (model.length > 160 || language.isEmpty || language.length > 40) {
      throw const FormatException('模型名称或目标语言无效');
    }
  }
}

class WatchAiSettings extends ChangeNotifier {
  WatchAiSettings({
    this.directory,
    this.readSecret = NativeBridge.secretRead,
    this.writeSecret = NativeBridge.secretWrite,
  });
  static final I = WatchAiSettings();
  final Directory? directory;
  final Future<String?> Function(String) readSecret;
  final Future<void> Function(String, String) writeSecret;
  WatchAiConfig config = const WatchAiConfig();
  Future<void> _writes = Future.value();
  static String secretKey(String endpoint) =>
      'watchAi.apiKey.${Uri.parse(endpoint).origin}';
  Future<File> _file() async {
    final dir =
        directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/SeeWow');
    await dir.create(recursive: true);
    return File('${dir.path}/watch-ai.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final next = WatchAiConfig.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      next.validate();
      config = next;
      notifyListeners();
    } catch (_) {
      config = const WatchAiConfig();
    }
  }

  Future<void> configure(WatchAiConfig next, {String apiKey = ''}) async {
    next.validate();
    if (apiKey.trim().isNotEmpty && next.endpoint.isNotEmpty) {
      await writeSecret(secretKey(next.endpoint), apiKey.trim());
    }
    final snapshot = jsonEncode(next.toJson());
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final f = await _file();
      final temp = File('${f.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(f.path);
    });
    await _writes;
    config = next;
    notifyListeners();
  }
}
