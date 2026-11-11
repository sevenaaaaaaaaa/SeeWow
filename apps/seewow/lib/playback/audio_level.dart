import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../domain/media_item.dart';
import '../metadata/metadata_transport.dart';
import 'audio_capture.dart';

class AudioLevel extends ChangeNotifier {
  AudioLevel(this.player);
  final Player player;
  final AudioCapture _capture = AudioCapture();
  MediaItem? source;
  Timer? _timer;
  WavAudio? _audio;
  double _start = 0;
  bool _reading = false, _disposed = false, _enabled = false, _visible = true;
  double? level;
  set visible(bool value) {
    _visible = value;
    if (!value) _capture.cancel();
  }

  Future<void> enable(bool value) async {
    _enabled = value;
    _timer?.cancel();
    if (!value) {
      await _capture.cancel();
      _audio = null;
      level = null;
    }
    if (value && !_disposed)
      _timer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _read(),
      );
  }

  Future<void> _read() async {
    if (_disposed || _reading || !_enabled || !_visible || source == null)
      return;
    _reading = true;
    try {
      if (!player.state.playing || player.state.buffering) {
        level = 0;
      } else {
        final at = player.state.position.inMilliseconds / 1000;
        if (_audio == null || at < _start || at >= _start + _audio!.duration) {
          final remaining = player.state.duration.inMilliseconds / 1000 - at;
          if (remaining < .5) {
            level = 0;
            return;
          }
          _start = at;
          _audio = await _capture.capture(source!, at, math.min(4, remaining));
        }
        if (!_disposed)
          level = _audio!.levelAt(
            player.state.position.inMilliseconds / 1000 - _start,
            volume: player.state.volume,
          );
      }
      if (!_disposed) notifyListeners();
    } on MetadataCancelled {
      /* Hiding controls cancels pending sampling. */
    } catch (_) {
      level = null;
      _enabled = false;
      _timer?.cancel();
      if (!_disposed) notifyListeners();
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _capture.cancel();
    super.dispose();
  }
}
