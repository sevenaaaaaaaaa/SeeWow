import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';

/// Keychain / secrets-file key for a source.
String sourceSecretKey(MediaSource source) => 'source.' + source.id;

/// Host capabilities SeeWow needs but Flutter does not expose:
/// SMB mounting (NetFS on macOS) and secret storage (Keychain on macOS).
///
/// macOS goes through the runner channel; other platforms fall back to process
/// helpers plus a 0600 secrets file, so the app still runs before those
/// platforms get their own native bridge.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('seewow/native');

  static Future<String?> secretRead(String key) async {
    if (Platform.isMacOS) {
      try {
        return await _channel.invokeMethod<String>('secret.read', {'key': key});
      } on MissingPluginException {
        // fall through to file storage
      } on PlatformException catch (e) {
        throw NativeException(e.message ?? '读取凭据失败');
      }
    }
    return _fileSecrets.read(key);
  }

  static Future<void> secretWrite(String key, String value) async {
    if (Platform.isMacOS) {
      try {
        final ok = await _channel.invokeMethod<bool>('secret.write', {'key': key, 'value': value});
        if (ok == true) return;
      } on MissingPluginException {
        // fall through
      } on PlatformException {
        // fall through to file storage rather than losing the credential
      }
    }
    await _fileSecrets.write(key, value);
  }

  static Future<void> secretDelete(String key) async {
    if (Platform.isMacOS) {
      try {
        await _channel.invokeMethod<bool>('secret.delete', {'key': key});
      } on MissingPluginException {
        // ignore
      } on PlatformException {
        // ignore
      }
    }
    await _fileSecrets.delete(key);
  }

  /// Mounts an SMB share and returns a readable local path.
  static Future<String> smbMount({
    required String host,
    required String share,
    required String username,
    required String password,
    required String subpath,
    required String mountPoint,
  }) async {
    if (Platform.isMacOS) {
      try {
        final path = await _channel.invokeMethod<String>('smb.mount', {
          'host': host,
          'share': share,
          'username': username,
          'password': password,
          'subpath': subpath,
          'mountPoint': mountPoint,
        });
        if (path == null || path.isEmpty) throw NativeException('挂载成功但没有返回路径');
        return path;
      } on MissingPluginException {
        throw NativeException('SMB 桥接未就绪，请重新构建应用');
      } on PlatformException catch (e) {
        throw NativeException(e.message ?? 'SMB 挂载失败');
      }
    }
    if (Platform.isWindows) return _windowsMount(host, share, username, password, subpath);
    if (Platform.isLinux) return _linuxMount(host, share, subpath);
    throw NativeException('当前平台暂不支持 SMB 直连，请使用 WebDAV 或本地文件夹');
  }

  static Future<String> _windowsMount(String host, String share, String username, String password, String subpath) async {
    for (final drive in ['Z', 'Y', 'X', 'W', 'V', 'U', 'T', 'S']) {
      final target = '\\\\' + host + '\\' + share;
      final args = ['use', drive + ':', target, '/persistent:no'];
      if (username.isNotEmpty) args.addAll(['/user:' + username, password]);
      final r = await Process.run('net', args, runInShell: true);
      if (r.exitCode == 0) {
        final base = drive + ':\\';
        return subpath.isEmpty ? base : base + subpath;
      }
    }
    throw NativeException('无法建立 SMB 连接：请检查地址或凭据');
  }

  static Future<String> _linuxMount(String host, String share, String subpath) async {
    final uri = 'smb://' + host + '/' + share;
    final r = await Process.run('gio', ['mount', uri], runInShell: true);
    if (r.exitCode != 0) {
      throw NativeException('无法挂载 ' + uri + '。Linux 请先在「文件」中连接该共享（凭据存入密钥环），或改用 WebDAV。');
    }
    final uid = (await Process.run('id', ['-u'])).stdout.toString().trim();
    final root = Directory('/run/user/' + uid + '/gvfs');
    if (await root.exists()) {
      await for (final e in root.list()) {
        if (!e.path.contains('smb-share')) continue;
        if (e.path.contains('server=' + host) || e.path.contains(':server=' + host)) {
          return subpath.isEmpty ? e.path : e.path + '/' + subpath;
        }
      }
    }
    throw NativeException('挂载成功但找不到挂载点（' + uri + '）');
  }
}

class NativeException implements Exception {
  NativeException(this.message);
  final String message;
  @override
  String toString() => message;
}

final _FileSecrets _fileSecrets = _FileSecrets();

class _FileSecrets {
  Map<String, String>? _cache;

  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(support.path + '/SeeWow');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(dir.path + '/secrets.json');
  }

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    final f = await _file();
    if (!await f.exists()) return _cache = {};
    try {
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return _cache = raw.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return _cache = {};
    }
  }

  Future<void> _persist(Map<String, String> data) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(data));
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', f.path]);
    }
  }

  Future<String?> read(String key) async => (await _load())[key];

  Future<void> write(String key, String value) async {
    final data = await _load();
    data[key] = value;
    await _persist(data);
  }

  Future<void> delete(String key) async {
    final data = await _load();
    data.remove(key);
    await _persist(data);
  }
}
