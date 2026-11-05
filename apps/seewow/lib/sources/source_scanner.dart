import '../data/local_scanner.dart';
import '../domain/media_item.dart';
import 'native_bridge.dart';
import 'smb_mounter.dart';
import 'webdav_client.dart';
import 'webdav_scanner.dart';

/// Routes a MediaSource to the right scanner and keeps credentials out of the
/// library file: username lives on the source, the password lives in Keychain.
class SourceScanner {
  SourceScanner({LocalScanner? local}) : _local = local ?? LocalScanner();

  final LocalScanner _local;

  Future<List<MediaItem>> scan(MediaSource source) async {
    switch (source.kind) {
      case SourceKind.local:
        return _local.scan(source);
      case SourceKind.webdav:
        return _scanWebDav(source);
      case SourceKind.smb:
        return _scanSmb(source);
      default:
        return const [];
    }
  }

  Future<List<MediaItem>> _scanWebDav(MediaSource source) async {
    final base = Uri.tryParse(source.location.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw NativeException('WebDAV 地址格式应为 http(s)://主机/路径');
    }
    final normalized = base.path.endsWith('/') ? base : base.replace(path: base.path + '/');
    final password = await NativeBridge.secretRead(sourceSecretKey(source)) ?? '';
    final client = WebDavClient(normalized, username: source.username, password: password);
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
