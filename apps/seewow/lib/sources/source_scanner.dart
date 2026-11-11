import 'dart:convert';

import 'plex_scanner.dart';
import 'openlist_scanner.dart';
import 'synology_scanner.dart';
import 'navidrome_scanner.dart';

import '../data/local_scanner.dart';
import 'media_server_scanner.dart';
import '../domain/media_item.dart';
import 'native_bridge.dart';
import 'smb_mounter.dart';
import 'webdav_client.dart';
import 'webdav_scanner.dart';

/// Routes a MediaSource to the right scanner and keeps credentials out of the
/// library file: username lives on the source, the password lives in Keychain.
class SourceScanner {
  SourceScanner({
    LocalScanner? local,
    Future<String?> Function(String)? readSecret,
  }) : _local = local ?? LocalScanner(),
       _readSecret = readSecret ?? NativeBridge.secretRead;
  final Future<String?> Function(String) _readSecret;

  final LocalScanner _local;

  Future<List<MediaItem>> scan(MediaSource source) async {
    switch (source.kind) {
      case SourceKind.local:
        return _local.scan(source);
      case SourceKind.webdav:
        return _scanWebDav(source);
      case SourceKind.smb:
        return _scanSmb(source);
      case SourceKind.jellyfin:
      case SourceKind.emby:
        return MediaServerScanner().scan(
          source,
          await _readSecret(sourceSecretKey(source)) ?? '',
        );
      case SourceKind.plex:
        return PlexScanner().scan(
          source,
          await _readSecret(sourceSecretKey(source)) ?? '',
        );
      case SourceKind.openlist:
        final gateway = OpenListScanner(
          source,
          await _readSecret(sourceSecretKey(source)) ?? '',
        );
        try {
          return await gateway.scan();
        } finally {
          gateway.close();
        }
      case SourceKind.synology:
        final nas = SynologyScanner(
          source,
          await _readSecret(sourceSecretKey(source)) ?? '',
        );
        try {
          return await nas.scan();
        } finally {
          nas.close();
        }
      case SourceKind.navidrome:
        final music = NavidromeScanner(
          source,
          await _readSecret(sourceSecretKey(source)) ?? '',
        );
        try {
          return await music.scan();
        } finally {
          music.close();
        }
      default:
        throw UnsupportedError('${source.kind.name} 尚未接入，请使用 SMB 或 WebDAV');
    }
  }

  Future<Map<String, String>> headersFor(MediaSource source) async {
    if (![
      SourceKind.webdav,
      SourceKind.jellyfin,
      SourceKind.emby,
      SourceKind.plex,
    ].contains(source.kind))
      return const {};
    final secret = await _readSecret(sourceSecretKey(source)) ?? '';
    if (source.kind == SourceKind.webdav) {
      return source.username.isEmpty && secret.isEmpty
          ? const {}
          : {
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('${source.username}:$secret'))}',
            };
    }
    return secret.isEmpty
        ? const {}
        : {
            source.kind == SourceKind.plex ? 'X-Plex-Token' : 'X-Emby-Token':
                secret,
          };
  }

  Future<MediaItem> prepare(MediaItem item, MediaSource? source) async {
    if (source == null) {
      if (item.sourceRef != null) throw StateError('来源已移除，请重新连接');
      return item;
    }
    switch (source.kind) {
      case SourceKind.openlist:
        final gateway = OpenListScanner(
          source,
          await _readSecret(sourceSecretKey(source)) ?? '',
        );
        try {
          return await gateway.prepare(item);
        } finally {
          gateway.close();
        }
      case SourceKind.synology:
        final nas = SynologyScanner(
          source,
          await _readSecret(sourceSecretKey(source)) ?? '',
        );
        try {
          return await nas.prepare(item);
        } finally {
          nas.close();
        }
      case SourceKind.navidrome:
        final music = NavidromeScanner(
          source,
          await _readSecret(sourceSecretKey(source)) ?? '',
        );
        try {
          return music.prepare(item);
        } finally {
          music.close();
        }
      default:
        return item.copyWith(
          httpHeaders: {
            ...item.httpHeaders.wherePublic(),
            ...await headersFor(source),
          },
        );
    }
  }

  Future<List<MediaItem>> _scanWebDav(MediaSource source) async {
    final base = Uri.tryParse(source.location.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw NativeException('WebDAV 地址格式应为 http(s)://主机/路径');
    }
    final normalized = base.path.endsWith('/')
        ? base
        : base.replace(path: base.path + '/');
    final password = await _readSecret(sourceSecretKey(source)) ?? '';
    final client = WebDavClient(
      normalized,
      username: source.username,
      password: password,
    );
    try {
      return await WebDavScanner().scan(source, client);
    } finally {
      client.close();
    }
  }

  Future<List<MediaItem>> _scanSmb(MediaSource source) async {
    final path = await SmbMounter.instance.ensureMounted(source);
    final local = MediaSource(
      id: source.id,
      kind: SourceKind.local,
      name: source.name,
      location: path,
      enabled: source.enabled,
    );
    final items = await _local.scan(local);
    // Locators stay local file paths (mounted share), ids stay stable.
    return items;
  }
}
