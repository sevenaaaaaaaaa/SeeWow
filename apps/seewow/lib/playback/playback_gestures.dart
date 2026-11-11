import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Raw pointer tracking makes two-or-more-finger holds deterministic. Once a
/// multi-touch sequence starts, no remaining finger may seek or unmute.
class PlaybackGestures extends StatefulWidget {
  const PlaybackGestures({
    super.key,
    required this.child,
    required this.locked,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onTap,
    required this.onUnmute,
    required this.onToggleLock,
    required this.onPreview,
    this.seekEnabled = true,
  });
  final Widget child;
  final bool locked, seekEnabled;
  final double position, duration;
  final ValueChanged<double> onSeek;
  final ValueChanged<double?> onPreview;
  final VoidCallback onTap, onUnmute, onToggleLock;
  @override
  State<PlaybackGestures> createState() => _PlaybackGesturesState();
}

class _PlaybackGesturesState extends State<PlaybackGestures> {
  final _pointers = <int, Offset>{};
  final _origins = <int, Offset>{};
  Timer? _hold, _repeat, _tap;
  bool _multi = false, _lockFired = false, _seeking = false;
  Offset? _start;
  double _base = 0, _preview = 0, _width = 1;
  int _ticks = 0;
  DateTime? _lastTap;
  Offset? _lastTapPosition;
  void _cancelHold() {
    _hold?.cancel();
    _repeat?.cancel();
  }

  void _previewAt(double value) {
    _preview = value.clamp(0.0, widget.duration);
    widget.onPreview(_preview);
  }

  void _down(PointerDownEvent e) {
    // Touch and primary mouse/trackpad buttons only.
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton)
      return;
    _pointers[e.pointer] = e.localPosition;
    _origins[e.pointer] = e.localPosition;
    _cancelHold();
    if (_pointers.length >= 2) {
      _multi = true;
      _tap?.cancel();
      _lastTap = null;
      _seeking = false;
      widget.onPreview(null);
      if (!_lockFired) {
        _hold = Timer(const Duration(milliseconds: 650), () {
          if (mounted && _pointers.length >= 2 && !_lockFired) {
            _lockFired = true;
            widget.onToggleLock();
          }
        });
      }
      return;
    }
    _start = e.localPosition;
    _base = widget.position;
    _preview = _base;
    if (widget.locked || !widget.seekEnabled || widget.duration <= 0) return;
    _hold = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _multi || _pointers.length != 1 || widget.locked) return;
      _tap?.cancel();
      _lastTap = null;
      _seeking = true;
      _ticks = 0;
      final direction = _start!.dx < _width / 2 ? -1 : 1;
      void tick() {
        _ticks++;
        _previewAt(
          _preview +
              direction *
                  (_ticks > 15
                      ? 10
                      : _ticks > 5
                      ? 5
                      : 2),
        );
      }

      tick();
      _repeat = Timer.periodic(
        const Duration(milliseconds: 180),
        (_) => tick(),
      );
    });
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_multi) {
      if ((e.localPosition - _origins[e.pointer]!).distance > 24) _cancelHold();
      return;
    }
    if (widget.locked || _start == null) return;
    final delta = e.localPosition - _start!;
    if (!_seeking && delta.distance > 16) {
      _cancelHold();
      // Vertical gestures never turn into an unexpected seek.
      if (delta.dx.abs() <= delta.dy.abs() ||
          !widget.seekEnabled ||
          widget.duration <= 0) {
        _start = null;
        return;
      }
      _seeking = true;
      _tap?.cancel();
      _lastTap = null;
    }
    if (_seeking && _repeat?.isActive != true) {
      final span = (widget.duration * .2).clamp(30.0, 600.0);
      _previewAt(_base + delta.dx / _width * span);
    }
  }

  void _up(PointerEvent e, {bool cancelled = false}) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers.remove(e.pointer);
    _origins.remove(e.pointer);
    if (!_multi || _pointers.length < 2 || cancelled) _cancelHold();
    if (!_multi && !cancelled) {
      if (_seeking && !widget.locked) {
        widget.onSeek(_preview);
      } else if (_start != null && (e.localPosition - _start!).distance < 16) {
        if (widget.locked) {
          widget.onTap();
        } else {
          final now = DateTime.now();
          if (_lastTap != null &&
              now.difference(_lastTap!).inMilliseconds < 300 &&
              (e.localPosition - _lastTapPosition!).distance < 40) {
            _tap?.cancel();
            _lastTap = null;
            widget.onUnmute();
          } else {
            _lastTap = now;
            _lastTapPosition = e.localPosition;
            _tap?.cancel();
            _tap = Timer(const Duration(milliseconds: 300), () {
              _lastTap = null;
              if (mounted) widget.onTap();
            });
          }
        }
      }
    }
    _seeking = false;
    widget.onPreview(null);
    if (_pointers.isEmpty) {
      _multi = false;
      _lockFired = false;
      _start = null;
    }
  }

  @override
  void didUpdateWidget(PlaybackGestures oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locked != widget.locked) {
      _cancelHold();
      _tap?.cancel();
      _lastTap = null;
    }
  }

  @override
  void dispose() {
    _cancelHold();
    _tap?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      _width = constraints.maxWidth.isFinite ? constraints.maxWidth : 1;
      return SizedBox.expand(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: (e) => _up(e),
          onPointerCancel: (e) => _up(e, cancelled: true),
          child: widget.child,
        ),
      );
    },
  );
}
