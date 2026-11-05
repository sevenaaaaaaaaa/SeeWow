import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';
import 'native_bridge.dart';

/// Mounts an SMB share into Application Support and hands back a local path,
/// so scanning and playback reuse the exact same file:// pipeline as a USB
/// drive. Desktop uses the system client; mobile will need libsmb2 + a local
/// HTTP bridge instead.
class SmbMounter {
  static final SmbMounter instance = SmbMounter();
  final Map<String, String> _mounted = {};

  Future<String> ensureMounted(MediaSource source) async {
    final cached = _mounted[source.id];
    if (cached != null && await Directory(cached).exists()) return cached;

    final spec = parseSmbLocation(source.location);
    final support = await getApplicationSupportDirectory();
    final mountPoint = support.path + '/SeeWow/mounts/' + source.id;
    final password = await NativeBridge.secretRead(sourceSecretKey(source)) ?? '';
    final path = await NativeBridge.smbMount(
      host: spec.host,
      share: spec.share,
      username: source.username,
      password: password,
      subpath: spec.subpath,
      mountPoint: mountPoint,
    );
    _mounted[source.id] = path;
    return path;
  }

  static SmbSpec parseSmbLocation(String raw) {
    var text = raw.trim();
    if (text.isEmpty) throw NativeException('请填写 SMB 地址');
    if (!text.toLowerCase().startsWith('smb://')) text = 'smb://' + text;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      throw NativeException('SMB 地址格式应为 smb://主机/共享名');
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw NativeException('缺少共享名，例如 smb://192.168.1.10/media');
    }
    return SmbSpec(
      host: uri.host,
      share: segments.first,
      subpath: segments.skip(1).join('/'),
    );
  }
}

class SmbSpec {
  const SmbSpec({required this.host, required this.share, required this.subpath});
  final String host;
  final String share;
  final String subpath;
}
