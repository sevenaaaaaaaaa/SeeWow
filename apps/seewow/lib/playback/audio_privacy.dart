import 'dart:convert';
import 'dart:math' as math;

import '../sources/native_bridge.dart';

enum AudioOutputRoute { speaker, headphones, unknown }

/// Only positive, explicitly selected player gain is remembered. Mute is a
/// separate state and must never erase a quieter preference.
class DailyVolumeMemory {
  DailyVolumeMemory({DateTime Function()? now}) : now = now ?? DateTime.now;
  final DateTime Function() now;
  String? _day;
  final Map<String, double> _volumes = {};
  String get today {
    final d = now();
    return '${d.year}-${d.month}-${d.day}';
  }

  void _rollover() {
    if (_day == today) return;
    _day = today;
    _volumes.clear();
  }

  void restore(String? raw) {
    _rollover();
    try {
      final j = jsonDecode(raw ?? '') as Map;
      if (j['day'] != today) return;
      for (final route in ['speaker', 'headphones']) {
        final v = j[route];
        if (v is num && v.isFinite && v > 0 && v <= 100) {
          _volumes[route] = v.toDouble();
        }
      }
    } catch (_) {}
  }

  String _key(AudioOutputRoute route) =>
      route == AudioOutputRoute.headphones ? 'headphones' : 'speaker';
  double initial(AudioOutputRoute route) {
    _rollover();
    final ceiling = route == AudioOutputRoute.headphones ? 50.0 : 30.0;
    return math.min(ceiling, _volumes[_key(route)] ?? ceiling);
  }

  void remember(AudioOutputRoute route, double volume) {
    _rollover();
    if (volume.isFinite && volume > 0) {
      _volumes[_key(route)] = volume.clamp(0.0, 100.0);
    }
  }

  String encode() {
    _rollover();
    return jsonEncode({'day': _day, ..._volumes});
  }
}

/// All sound paths consume [effectiveVolume], including dubbed audio and PiP.
/// A positive detection is latched for this file; a later negative frame cannot
/// silently release the protection. Unknown/shared outputs count as speakers.
class AudioPrivacy {
  AudioPrivacy(this.memory);
  static const memoryKey = 'playback.volume.today';
  final DailyVolumeMemory memory;
  AudioOutputRoute route = AudioOutputRoute.unknown;
  double volume = 30;
  bool muted = true, sensitive = false;
  bool get blocked => sensitive && route != AudioOutputRoute.headphones;
  double get effectiveVolume => muted || blocked ? 0 : volume;
  String get routeLabel => switch (route) {
    AudioOutputRoute.headphones => '耳机',
    AudioOutputRoute.speaker => '外放',
    AudioOutputRoute.unknown => '输出未确认 · 按外放保护',
  };
  Future<void> load() async {
    try {
      memory.restore(await NativeBridge.secretRead(memoryKey));
    } catch (_) {}
    volume = memory.initial(route);
    // Expired values are overwritten, never retained as a listening history.
    await persist();
  }

  Future<void> persist() async {
    try {
      await NativeBridge.secretWrite(memoryKey, memory.encode());
    } catch (_) {}
  }

  void changeRoute(AudioOutputRoute next) {
    route = next;
    muted = true;
    volume = memory.initial(route);
  }

  void detectSensitive() {
    sensitive = true;
    if (blocked) muted = true;
  }

  bool unmute() {
    if (blocked) return false;
    volume = math.min(volume, memory.initial(route));
    muted = false;
    return true;
  }

  void selectVolume(double value) {
    if (!value.isFinite) return;
    volume = value.clamp(0.0, 100.0);
    // Explicitly raising the slider is allowed, but cannot release NSFW mute.
    muted = volume == 0 || blocked;
    memory.remember(route, volume);
  }
}
