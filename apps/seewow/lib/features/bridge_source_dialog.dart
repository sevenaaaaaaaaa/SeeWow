import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../domain/media_item.dart';
import '../remote/remote_client.dart';
import '../sources/native_bridge.dart';

/// Connects a phone to a desktop SeeWow library over the LAN. The desktop
/// resolves SMB files and authenticated streams, so the phone never needs an
/// SMB client or provider tokens.
Future<void> connectBridgeLibrary(
  BuildContext context,
  LibraryStore store,
) async {
  final config = await showDialog<_BridgeConfig>(
    context: context,
    builder: (_) => const _BridgeDialog(),
  );
  if (config == null || !context.mounted) return;
  final source = MediaSource(
    id: 'bridge-${DateTime.now().microsecondsSinceEpoch}',
    kind: SourceKind.bridge,
    name: '电脑媒体库 · ${config.host}',
    location: 'http://${config.host}:${config.port}',
  );
  try {
    await NativeBridge.secretWrite(sourceSecretKey(source), config.token);
    await store.addSource(source);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已连接电脑媒体库，正在扫描')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('连接失败：$error')));
    }
  }
}

class _BridgeConfig {
  const _BridgeConfig(this.host, this.port, this.token);
  final String host;
  final int port;
  final String token;
}

class _BridgeDialog extends StatefulWidget {
  const _BridgeDialog();
  @override
  State<_BridgeDialog> createState() => _BridgeDialogState();
}

class _BridgeDialogState extends State<_BridgeDialog> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '47834');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _found;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await RemoteClient().discover();
      if (devices.isEmpty) {
        setState(() => _error = '没有发现电脑，请确认同一 Wi-Fi 并开启「手机遥控电脑」');
        return;
      }
      final device = devices.first;
      _host.text = device.host;
      _port.text = '${device.port}';
      setState(() => _found = device.label);
    } catch (error) {
      setState(() => _error = '搜索失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    final code = _code.text.trim();
    if (host.isEmpty || port <= 0) {
      setState(() => _error = '填写电脑地址与端口');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = '填写电脑上显示的 6 位配对码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = RemoteClient()..configure(host, port);
      await client.pair(code, device: '手机媒体库');
      final token = client.token;
      if (token == null) throw const FormatException('电脑没有返回访问令牌');
      if (!mounted) return;
      Navigator.pop(context, _BridgeConfig(host, port, token));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('电脑媒体库（局域网）'),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '在电脑上打开 设置 → 手机遥控电脑，开启开关后把显示的地址和配对码填到这里。'
            '电脑会负责读取 SMB 与带令牌的 Plex / Emby 片源，手机无需挂载共享。',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _host,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '电脑地址',
              hintText: '192.168.1.10',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '配对码',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _port,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '端口'),
                ),
              ),
            ],
          ),
          if (_found != null) ...[
            const SizedBox(height: 8),
            Text(
              '发现：$_found',
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton.icon(
        onPressed: _busy ? null : _discover,
        icon: const Icon(Icons.wifi_find, size: 17),
        label: const Text('搜索电脑'),
      ),
      FilledButton(
        onPressed: _busy ? null : _connect,
        child: _busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('连接并扫描'),
      ),
    ],
  );
}
