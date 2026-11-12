import 'dart:async';

/// Playback surface the desktop exposes to a paired phone.
abstract class RemotePlayback {
  String get remoteTitle;
  Duration get remotePosition;
  Duration get remoteDuration;
  bool get remotePlaying;
  double get remoteVolume;
  Future<void> remoteToggle();
  Future<void> remoteSeek(Duration position);
  Future<void> remoteSetVolume(double volume);
}

/// One open player can be remote-controlled at a time.
class RemoteHub {
  RemoteHub._();
  static final RemoteHub instance = RemoteHub._();

  RemotePlayback? _active;
  RemotePlayback? get active => _active;
  bool get hasPlayback => _active != null;

  void attach(RemotePlayback playback) => _active = playback;
  void detach(RemotePlayback playback) {
    if (identical(_active, playback)) _active = null;
  }
}
