import 'dart:async';

import '../domain/media_item.dart';

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

/// One item exposed to the paired phone. Never includes file paths or tokens.
class RemoteLibraryItem {
  const RemoteLibraryItem({
    required this.id,
    required this.title,
    required this.year,
    required this.kind,
    required this.duration,
  });
  final String id, title, kind;
  final int year;
  final int duration;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'year': year,
    'kind': kind,
    'duration': duration,
  };
}

/// The desktop app registers this to let a phone browse the library and open
/// an item on the big screen.
abstract class RemoteLibraryHost {
  Future<List<RemoteLibraryItem>> remoteItems();
  Future<bool> remoteOpen(String id);
}

/// Desktop-side bridge used by the phone's "computer library" source.
/// It exposes real library items over the LAN so phones can play SMB files and
/// authenticated Plex/Emby streams without needing headers.
abstract class RemoteBridgeHost {
  List<MediaItem> get bridgeItems;
  Future<MediaItem?> bridgeItem(String id);
  Future<MediaItem> bridgePrepare(MediaItem item);
}

/// One open player can be remote-controlled at a time.
class RemoteHub {
  RemoteHub._();
  static final RemoteHub instance = RemoteHub._();

  RemotePlayback? _active;
  RemotePlayback? get active => _active;
  bool get hasPlayback => _active != null;

  RemoteLibraryHost? library;

  void attach(RemotePlayback playback) => _active = playback;
  void detach(RemotePlayback playback) {
    if (identical(_active, playback)) _active = null;
  }
}
