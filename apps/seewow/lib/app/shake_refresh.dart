import 'package:flutter/foundation.dart';

/// Recognises a deliberate back-and-forth motion on one axis.
///
/// Used for two different sensors with one piece of logic: the phone's
/// accelerometer (x axis in m/s²) and a desktop window being shaken (x axis in
/// pixels). Both look the same from here — a value that keeps reversing.
///
/// Deliberately strict, because a false positive reloads the whole library
/// while somebody is watching a film.
class ReversalShakeDetector {
  ReversalShakeDetector({
    this.minAmplitude = 36,
    this.window = const Duration(milliseconds: 1100),
    this.minReversals = 3,
    this.cooldown = const Duration(milliseconds: 2500),
  });

  /// How far the value must travel before a direction change counts.
  final double minAmplitude;

  /// Reversals older than this are forgotten.
  final Duration window;

  /// How many direction changes inside [window] make a shake.
  final int minReversals;

  /// After a trigger nothing is reported for this long.
  final Duration cooldown;

  double _anchor = double.nan;
  int _direction = 0;
  DateTime? _lastTrigger;
  final List<DateTime> _reversals = [];

  /// Feeds one sample. Returns true only on the sample that completes a shake.
  bool add(double value, DateTime at) {
    final last = _lastTrigger;
    if (last != null && at.difference(last) < cooldown) return false;

    if (_anchor.isNaN) {
      _anchor = value;
      return false;
    }
    final delta = value - _anchor;
    if (delta.abs() < minAmplitude) return false;

    final direction = delta > 0 ? 1 : -1;
    _anchor = value;
    if (_direction == 0) {
      _direction = direction;
      return false;
    }
    if (direction == _direction) return false;

    _direction = direction;
    _reversals
      ..removeWhere((t) => at.difference(t) > window)
      ..add(at);
    if (_reversals.length < minReversals) return false;

    _reversals.clear();
    _direction = 0;
    _lastTrigger = at;
    return true;
  }

  void reset() {
    _anchor = double.nan;
    _direction = 0;
    _reversals.clear();
  }
}

/// Decides whether a shake is allowed to mean "refresh" right now.
///
/// A refresh while a film is playing, or three seconds after the user touched
/// something, is never what they meant.
class RefreshGestureGate {
  RefreshGestureGate({
    this.idleAfter = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration idleAfter;
  final DateTime Function() _clock;

  bool _playing = false;
  DateTime? _lastInteraction;

  bool get playing => _playing;

  set playing(bool value) {
    _playing = value;
    _lastInteraction = value ? _clock() : _lastInteraction;
  }

  void markInteraction() => _lastInteraction = _clock();

  bool get armed {
    if (_playing) return false;
    final last = _lastInteraction;
    if (last == null) return true;
    return _clock().difference(last) >= idleAfter;
  }
}

/// Platform-neutral description of what the shake surface should do.
///
/// The widget layer owns the sensors; this type only says which of them exist,
/// so a test can assert the desktop and the phone take different paths.
enum ShakeSurface {
  /// Phone / tablet: real accelerometer.
  accelerometer,

  /// Desktop: no accelerometer exists, so the window itself is shaken.
  window,

  /// Neither is available (e.g. a web preview): keep the button.
  none,
}

ShakeSurface shakeSurfaceFor({
  required bool isMobile,
  required bool isDesktop,
  required bool sensorsAvailable,
}) {
  if (isMobile && sensorsAvailable) return ShakeSurface.accelerometer;
  if (isDesktop) return ShakeSurface.window;
  return ShakeSurface.none;
}

/// Small helper so the widget layer does not repeat the same guard.
class ShakeRefreshController extends ChangeNotifier {
  ShakeRefreshController({
    required this.gate,
    required this.onRefresh,
    ReversalShakeDetector? detector,
  }) : detector = detector ?? ReversalShakeDetector();

  final RefreshGestureGate gate;
  final Future<void> Function() onRefresh;
  final ReversalShakeDetector detector;

  bool _firing = false;

  bool get busy => _firing;

  Future<void> feed(double value, DateTime at) async {
    if (_disposed) return;
    if (_firing || !gate.armed) {
      detector.reset();
      return;
    }
    if (!detector.add(value, at)) return;
    _firing = true;
    notifyListeners();
    try {
      await onRefresh();
    } finally {
      _firing = false;
      if (!_disposed) notifyListeners();
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
