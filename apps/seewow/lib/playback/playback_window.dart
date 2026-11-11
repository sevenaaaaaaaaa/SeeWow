import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// One native desktop window, preserving the entire player/control route.
class PlaybackWindow extends ChangeNotifier with WindowListener {
  static const channel = MethodChannel('seewow/playback');
  static bool get desktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  Rect? _bounds;
  bool? _wasFullscreen, _wasOnTop;
  bool mini = false, fullscreen = false;
  bool _closed = false;
  bool _registered = false;
  static Future<void> _work = Future.value();
  Completer<void>? _transition;
  bool? _transitionTarget;
  Future<void> _setFullscreen(bool target) async {
    if (await windowManager.isFullScreen() == target) return;
    final done = Completer<void>();
    _transition = done;
    _transitionTarget = target;
    try {
      await windowManager.setFullScreen(target);
      await done.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () async {
          if (await windowManager.isFullScreen() != target)
            throw const FormatException('系统全屏切换未完成，请重试');
        },
      );
    } finally {
      if (identical(_transition, done)) {
        _transition = null;
        _transitionTarget = null;
      }
    }
  }

  Future<void> _serial(Future<void> Function() action) {
    final result = _work.catchError((Object _) {}).then((_) => action());
    _work = result;
    return result;
  }

  Future<void> begin({bool enterFullscreen = true}) => _serial(() async {
    if (!desktop || _closed) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    _registered = true;
    _bounds = await windowManager.getBounds();
    _wasFullscreen = await windowManager.isFullScreen();
    _wasOnTop = await windowManager.isAlwaysOnTop();
    if (enterFullscreen) await _setFullscreen(true);
    fullscreen = enterFullscreen || _wasFullscreen!;
  });
  Future<void> toggleFullscreen() => _serial(() async {
    if (!desktop || _closed) return;
    if (mini) await _restoreMini();
    fullscreen = !(await windowManager.isFullScreen());
    await _setFullscreen(fullscreen);
  });
  Future<void> toggleMini() => _serial(() async {
    if (!desktop || _closed) return;
    if (mini) {
      await _restoreMini();
      return;
    }
    await _setFullscreen(false);
    fullscreen = false;
    await windowManager.setMinimumSize(const Size(280, 180));
    await windowManager.setSize(const Size(480, 300));
    await windowManager.setAlwaysOnTop(true);
    mini = true;
  });
  Future<void> _restoreMini() async {
    await windowManager.setAlwaysOnTop(_wasOnTop ?? false);
    await windowManager.setMinimumSize(const Size(360, 360));
    if (_bounds != null) await windowManager.setBounds(_bounds!);
    mini = false;
  }

  Future<void> close() {
    _closed = true;
    return _serial(() async {
      try {
        if (!desktop || _bounds == null) return;
        if (mini) await _restoreMini();
        await _setFullscreen(_wasFullscreen ?? false);
        if (_wasFullscreen != true) await windowManager.setBounds(_bounds!);
        await windowManager.setMinimumSize(const Size(900, 640));
        await windowManager.setAlwaysOnTop(_wasOnTop ?? false);
      } finally {
        if (_registered) {
          windowManager.removeListener(this);
          _registered = false;
        }
      }
    });
  }

  @override
  void onWindowEnterFullScreen() {
    fullscreen = true;
    if (_transitionTarget == true && _transition?.isCompleted == false)
      _transition!.complete();
    if (!_closed) notifyListeners();
  }

  @override
  void onWindowLeaveFullScreen() {
    fullscreen = false;
    if (_transitionTarget == false && _transition?.isCompleted == false)
      _transition!.complete();
    if (!_closed) notifyListeners();
  }
}
