import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../sources/native_bridge.dart';
import 'sensitive_content.dart';

enum EntranceStyle { disc, spotlight, none }

class PlaybackPreferences extends ChangeNotifier {
  static final I = PlaybackPreferences();
  EntranceStyle entrance = EntranceStyle.disc;
  bool fullscreen = true, background = false, meter = true;
  bool sensitiveScan = false;
  String sensitiveEndpoint = '';
  static const key = 'playback.preferences';
  Future<void> load() async {
    try {
      final raw = await NativeBridge.secretRead(key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      entrance =
          EntranceStyle.values
              .where((s) => s.name == j['entrance'])
              .firstOrNull ??
          EntranceStyle.disc;
      fullscreen = j['fullscreen'] != false;
      background = j['background'] == true;
      meter = j['meter'] != false;
      sensitiveEndpoint = j['sensitiveEndpoint'] as String? ?? '';
      sensitiveScan = j['sensitiveScan'] == true;
      if (sensitiveScan) {
        try {
          SensitiveContentClient.validateEndpoint(sensitiveEndpoint);
        } catch (_) {
          sensitiveScan = false;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> save({
    required EntranceStyle entrance,
    required bool fullscreen,
    required bool background,
    required bool meter,
    bool sensitiveScan = false,
    String sensitiveEndpoint = '',
  }) async {
    if (sensitiveScan)
      SensitiveContentClient.validateEndpoint(sensitiveEndpoint);
    await NativeBridge.secretWrite(
      key,
      jsonEncode({
        'entrance': entrance.name,
        'fullscreen': fullscreen,
        'background': background,
        'meter': meter,
        'sensitiveScan': sensitiveScan,
        'sensitiveEndpoint': sensitiveEndpoint.trim(),
      }),
    );
    this.entrance = entrance;
    this.fullscreen = fullscreen;
    this.background = background;
    this.meter = meter;
    this.sensitiveScan = sensitiveScan;
    this.sensitiveEndpoint = sensitiveEndpoint.trim();
    notifyListeners();
  }
}

class AbLoop {
  double? a, b;
  bool get enabled => a != null && b != null;
  String mark(double seconds) {
    if (!seconds.isFinite || seconds < 0)
      throw const FormatException('当前播放时间无效');
    if (a == null || enabled) {
      a = seconds;
      b = null;
      return '已标记 A 点';
    }
    if (seconds - a! < .5) throw const FormatException('B 点需在 A 点之后至少 0.5 秒');
    b = seconds;
    return 'AB 循环已开启';
  }

  void clear() {
    a = null;
    b = null;
  }
}

double? normalizedLoudness(String value, {double volume = 100}) {
  if (value == '-inf') return 0;
  final db = double.tryParse(value);
  if (db == null || !db.isFinite) return null;
  return ((db + 60) / 60).clamp(0.0, 1.0) * (volume / 100).clamp(0.0, 1.0);
}

String playbackTime(double seconds) {
  final total = seconds.isFinite ? seconds.round().clamp(0, 359999) : 0;
  final h = total ~/ 3600, m = total ~/ 60 % 60, s = total % 60;
  return '${h > 0 ? '$h:' : ''}${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
