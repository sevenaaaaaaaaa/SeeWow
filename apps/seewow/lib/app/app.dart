import 'dart:io';

import 'package:flutter/material.dart';

import '../data/iptv_store.dart';
import '../data/library_store.dart';
import '../sources/native_bridge.dart';
import '../sources/source_scanner.dart';
import '../design/skin.dart';
import '../watch_ai/watch_ai_settings.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../playback/playback_preferences.dart';
import '../remote/remote_server.dart';
import '../remote/remote_settings.dart';
import 'app_shell.dart';

class SeeWowApp extends StatefulWidget {
  const SeeWowApp({super.key});
  @override
  State<SeeWowApp> createState() => _SeeWowAppState();
}

class _SeeWowAppState extends State<SeeWowApp> {
  final LibraryStore _store = LibraryStore();
  final IPTVStore _iptv = IPTVStore();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await WowSkin.I.load();
    await WatchAiSettings.I.load();
    await PlaybackPreferences.I.load();
    await RemoteSettings.instance.load();
    if (RemoteSettings.instance.enabled) {
      try {
        await RemoteServer.instance.start(
          code: RemoteSettings.instance.code,
          name: Platform.localHostname,
        );
      } catch (_) {
        // The switch page explains and retries if the port is unavailable.
      }
    }
    await _store.load();
    await _iptv.load();
    final scanner = SourceScanner();
    _store.scanner = scanner.scan;
    await _store.hydrateCredentials(scanner.headersFor);
    final demo = _demoPath();
    if (demo != null) {
      final exists = _store.sources.any((s) => s.location == demo);
      if (!exists) {
        await _store.addSource(
          MediaSource(
            id: 'demo-' + demo.hashCode.toString(),
            kind: SourceKind.local,
            name: '演示片库',
            location: demo,
          ),
        );
      } else if (_store.items.isEmpty) {
        await _store.rescan(
          _store.sources.firstWhere((s) => s.location == demo),
        );
      }
    }
    if (Platform.environment['SEEWOW_SMB_PROBE'] == '1') {
      try {
        await NativeBridge.secretWrite('probe.key', 'swd');
        final back = await NativeBridge.secretRead('probe.key');
        await NativeBridge.secretDelete('probe.key');
        debugPrint(
          'SEEWOW_PROBE keychain=' +
              (back == 'swd' ? 'ok' : 'mismatch:' + back.toString()),
        );
      } catch (e) {
        debugPrint('SEEWOW_PROBE keychain=fail ' + e.toString());
      }
      try {
        final path = await NativeBridge.smbMount(
          host: 'seewow-probe.invalid',
          share: 'probe',
          username: 'nobody',
          password: 'nopass',
          subpath: '',
          mountPoint: '/tmp/seewow-smb-probe',
        );
        debugPrint('SEEWOW_PROBE smb=ok ' + path);
      } on NativeException catch (e) {
        debugPrint('SEEWOW_PROBE smb=' + e.message);
      } catch (e) {
        debugPrint('SEEWOW_PROBE smb=fail ' + e.toString());
      }
    }
    final dav = Platform.environment['SEEWOW_ADD_WEBDAV'];
    if (dav != null && dav.isNotEmpty) {
      final parts = dav.split('|');
      if (parts.length >= 2) {
        final name = parts[0];
        final url = parts[1];
        final user = parts.length > 2 ? parts[2] : '';
        final pass = parts.length > 3 ? parts[3] : '';
        final exists = _store.sources.any((s) => s.location == url);
        if (!exists || _store.items.isEmpty) {
          final source = MediaSource(
            id: 'dav-' + DateTime.now().millisecondsSinceEpoch.toString(),
            kind: SourceKind.webdav,
            name: name,
            location: url,
            username: user,
          );
          if (pass.isNotEmpty)
            await NativeBridge.secretWrite(sourceSecretKey(source), pass);
          if (exists) {
            await _store.rescan(
              _store.sources.firstWhere((s) => s.location == url),
            );
          } else {
            await _store.addSource(source);
          }
        }
      }
    }
    if (Platform.environment['SEEWOW_RESCAN'] == '1') {
      for (final source in List<MediaSource>.from(_store.sources)) {
        await _store.rescan(source);
      }
    }
    final iptvDemo = Platform.environment['SEEWOW_IPTV_DEMO'];
    if (iptvDemo != null && iptvDemo.isNotEmpty && _iptv.playlists.isEmpty) {
      await _iptv.addPlaylist(
        name: '演示直播源',
        source: iptvDemo,
        epgUrl: Platform.environment['SEEWOW_IPTV_EPG'],
      );
    }
    if (mounted) setState(() => _ready = true);
  }

  String? _demoPath() {
    final env = Platform.environment['SEEWOW_DEMO_PATH'];
    if (env != null && Directory(env).existsSync())
      return Directory(env).absolute.path;
    // Walk up from cwd and from the executable, so `flutter run`, a packaged
    // .app and a raw binary all find the dev sample library.
    final roots = <String>[
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
    ];
    for (final root in roots) {
      var dir = Directory(root);
      for (var depth = 0; depth < 12; depth++) {
        final candidate = Directory('${dir.path}/DemoMedia');
        if (candidate.existsSync()) return candidate.absolute.path;
        if (dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: WowSkin.I,
      builder: (context, _) => MaterialApp(
        title: 'SeeWow',
        debugShowCheckedModeBanner: false,
        theme: buildWowTheme(),
        home: _ready
            ? AppShell(store: _store, iptv: _iptv)
            : const _BootScreen(),
      ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WowColors.ink,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SeeWow',
              style: WowType.display(34, FontWeight.w600, spacing: -0.6),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 1.5,
                backgroundColor: WowColors.line,
                valueColor: AlwaysStoppedAnimation(WowColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
