import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../remote/remote_client.dart';
import '../remote/remote_hub.dart';
import '../remote/remote_server.dart';
import '../remote/remote_settings.dart';

Future<void> showRemoteControl(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            Platform.isMacOS || Platform.isWindows || Platform.isLinux
            ? const RemoteHostPage()
            : const RemoteClientPage(),
      ),
    );

String _clock(Duration value) {
  final total = value.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = minutes.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:$mm:${seconds.toString().padLeft(2, '0')}'
      : '$mm:${seconds.toString().padLeft(2, '0')}';
}

/// Desktop: turns this computer into a remote target.
class RemoteHostPage extends StatefulWidget {
  const RemoteHostPage({super.key});
  @override
  State<RemoteHostPage> createState() => _RemoteHostPageState();
}

class _RemoteHostPageState extends State<RemoteHostPage> {
  final _settings = RemoteSettings.instance;
  final _server = RemoteServer.instance;
  final _copied = ValueNotifier<String>('');
  Timer? _ticker;
  List<String> _addresses = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _copied.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_server.running) _addresses = await _server.addresses();
    if (mounted) setState(() {});
  }

  Future<void> _toggle(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (enabled) {
        if (_settings.code.length != 6) _settings.rotateCode();
        await _server.start(code: _settings.code, name: Platform.localHostname);
        _addresses = await _server.addresses();
      } else {
        await _server.stop();
      }
      _settings.enabled = enabled;
      await _settings.save();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    final code = _settings.rotateCode();
    _server.rotateCode(code);
    await _settings.save();
    if (mounted) setState(() {});
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    _copied.value = label;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label 已复制'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WowColors.ink,
    appBar: AppBar(backgroundColor: WowColors.ink, title: const Text('手机遥控电脑')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '在同一 Wi-Fi 下，用手机上的 SeeWow 控制这台电脑的播放。遥控只在局域网内生效，需要配对码。',
          style: WowType.body(13, color: WowColors.muted),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('允许手机遥控'),
          subtitle: Text(_busy ? '正在准备…' : (_server.running ? '已开启' : '已关闭')),
          value: _settings.enabled && _server.running,
          onChanged: _busy ? null : _toggle,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: WowColors.error)),
          ),
        if (_server.running) ...[
          const Divider(height: 32),
          Text('配对码', style: WowType.body(12, color: WowColors.muted)),
          const SizedBox(height: 6),
          Row(
            children: [
              SelectableText(
                _server.pairingCode,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                tooltip: '复制配对码',
                onPressed: () => _copy(_server.pairingCode, '配对码'),
                icon: const Icon(Icons.copy, size: 18),
              ),
              TextButton(onPressed: _rotate, child: const Text('换一个')),
            ],
          ),
          const SizedBox(height: 16),
          Text('电脑地址', style: WowType.body(12, color: WowColors.muted)),
          const SizedBox(height: 6),
          for (final address in _addresses)
            SelectableText(
              '$address:${_server.httpPort}',
              style: const TextStyle(fontSize: 16),
            ),
          if (_addresses.isEmpty)
            Text(
              '未找到局域网地址，请确认已连接 Wi-Fi 或网线',
              style: TextStyle(fontSize: 13, color: WowColors.error),
            ),
          const SizedBox(height: 6),
          Text(
            '手机端：设置 → 手机遥控 → 搜索电脑或手动输入上面的地址，再输入配对码。',
            style: WowType.body(12, color: WowColors.muted),
          ),
          const SizedBox(height: 12),
          Text(
            '已配对设备：${_server.pairedDevices}',
            style: WowType.body(12, color: WowColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            '首次开启时 macOS 可能询问是否允许 SeeWow 接受传入连接，请选择允许。',
            style: WowType.body(12, color: WowColors.muted),
          ),
        ],
      ],
    ),
  );
}

/// Phone: discovers a desktop and drives its player.
class RemoteClientPage extends StatefulWidget {
  const RemoteClientPage({super.key});
  @override
  State<RemoteClientPage> createState() => _RemoteClientPageState();
}

class _RemoteClientPageState extends State<RemoteClientPage> {
  final _client = RemoteClient();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '47834');
  final _code = TextEditingController();
  List<RemoteDevice> _devices = [];
  Timer? _poll;
  bool _scanning = false;
  bool _connecting = false;
  RemoteStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _client.close();
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final devices = await _client.discover();
      if (mounted) setState(() => _devices = devices);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pair() async {
    final port = int.tryParse(_port.text.trim()) ?? 47834;
    if (_host.text.trim().isEmpty || _code.text.trim().length != 6) {
      setState(() => _error = '请填写电脑地址和 6 位配对码');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      _client.configure(_host.text.trim(), port);
      await _client.pair(_code.text);
      final status = await _client.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _devices = [];
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _tick() async {
    if (!_client.paired) return;
    try {
      final status = await _client.status();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = null;
        });
      }
    }
  }

  Future<void> _command(String action, [num? value]) async {
    try {
      final status = await _client.command(action, value);
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _disconnect() {
    _poll?.cancel();
    _client.close();
    setState(() {
      _status = null;
      _devices = [];
    });
    _scan();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WowColors.ink,
    appBar: AppBar(backgroundColor: WowColors.ink, title: const Text('手机遥控电脑')),
    body: _status == null ? _buildConnect() : _buildRemote(_status!),
  );

  Widget _buildConnect() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        '让手机遥控电脑上的 SeeWow。确保手机和电脑在同一 Wi-Fi，然后在电脑「设置 → 手机遥控电脑」中开启并取得配对码。',
        style: WowType.body(13, color: WowColors.muted),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          FilledButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar, size: 18),
            label: Text(_scanning ? '正在搜索…' : '搜索电脑'),
          ),
        ],
      ),
      if (_devices.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final device in _devices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.computer, color: WowColors.accent),
            title: Text(device.name),
            subtitle: Text('${device.host}:${device.port}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _host.text = device.host;
              _port.text = '${device.port}';
              setState(() {});
            },
          ),
      ],
      const Divider(height: 36),
      Text('手动连接', style: WowType.body(12, color: WowColors.muted)),
      const SizedBox(height: 8),
      TextField(
        controller: _host,
        decoration: const InputDecoration(
          labelText: '电脑地址',
          hintText: '192.168.1.10',
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _port,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '端口'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(labelText: '6 位配对码', counterText: ''),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _connecting ? null : _pair,
        child: Text(_connecting ? '正在配对…' : '配对并连接'),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(_error!, style: TextStyle(color: WowColors.error)),
        ),
    ],
  );

  Future<void> _browse() async {
    final opened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _RemoteLibraryPage(client: _client)),
    );
    if (opened == true) await _tick();
  }

  Widget _buildRemote(RemoteStatus status) {
    final duration = status.duration;
    final max = duration.inMilliseconds
        .toDouble()
        .clamp(1.0, double.infinity)
        .toDouble();
    final position = status.position.inMilliseconds.toDouble().clamp(0, max);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          status.hasPlayback ? status.title : '电脑没有正在播放的影片',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          status.hasPlayback
              ? '${_clock(status.position)} / ${_clock(duration)}'
              : '在电脑上打开一部影片后再控制',
          style: WowType.body(12, color: WowColors.muted),
        ),
        const SizedBox(height: 20),
        Slider(
          value: position.clamp(0, max).toDouble(),
          max: max,
          onChanged: status.hasPlayback
              ? (value) => setState(
                  () => _status = RemoteStatus(
                    hasPlayback: status.hasPlayback,
                    title: status.title,
                    position: Duration(milliseconds: value.round()),
                    duration: status.duration,
                    playing: status.playing,
                    volume: status.volume,
                  ),
                )
              : null,
          onChangeEnd: status.hasPlayback
              ? (value) => _command('seek', value / 1000)
              : null,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 30,
              tooltip: '后退 10 秒',
              onPressed: status.hasPlayback
                  ? () => _command('seekRelative', -10)
                  : null,
              icon: const Icon(Icons.replay_10),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: status.hasPlayback ? () => _command('toggle') : null,
              child: Icon(
                status.playing ? Icons.pause : Icons.play_arrow,
                size: 30,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              iconSize: 30,
              tooltip: '前进 10 秒',
              onPressed: status.hasPlayback
                  ? () => _command('seekRelative', 10)
                  : null,
              icon: const Icon(Icons.forward_10),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            IconButton(
              tooltip: '音量 -',
              onPressed: status.hasPlayback
                  ? () => _command('volume', (status.volume - 5).clamp(0, 100))
                  : null,
              icon: const Icon(Icons.volume_down),
            ),
            Expanded(
              child: LinearProgressIndicator(
                value: status.volume / 100,
                minHeight: 6,
              ),
            ),
            IconButton(
              tooltip: '音量 +',
              onPressed: status.hasPlayback
                  ? () => _command('volume', (status.volume + 5).clamp(0, 100))
                  : null,
              icon: const Icon(Icons.volume_up),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: WowColors.error)),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _browse,
          icon: const Icon(Icons.video_library_outlined, size: 18),
          label: const Text('浏览电脑片库'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _disconnect,
          icon: const Icon(Icons.link_off, size: 18),
          label: const Text('断开连接'),
        ),
      ],
    );
  }
}

class _RemoteLibraryPage extends StatefulWidget {
  const _RemoteLibraryPage({required this.client});
  final RemoteClient client;
  @override
  State<_RemoteLibraryPage> createState() => _RemoteLibraryPageState();
}

class _RemoteLibraryPageState extends State<_RemoteLibraryPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<RemoteLibraryItem> _items = [];
  bool _loading = true;
  String? _error;
  String? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.client.library(query: _search.text);
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _open(RemoteLibraryItem item) async {
    setState(() => _opening = item.id);
    try {
      await widget.client.open(item.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _opening = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WowColors.ink,
    appBar: AppBar(backgroundColor: WowColors.ink, title: const Text('电脑片库')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onQueryChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索片名',
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: WowColors.error, fontSize: 12),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? const Center(child: Text('片库里没有找到影片'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: WowColors.line),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      title: Text(item.title, maxLines: 1),
                      subtitle: Text(
                        '${item.year > 0 ? item.year : ''} · '
                        '${_kindLabel(item.kind)} · '
                        '${_clock(Duration(seconds: item.duration))}',
                      ),
                      trailing: _opening == item.id
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_circle_outline),
                      onTap: _opening == null ? () => _open(item) : null,
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

String _kindLabel(String kind) => switch (kind) {
  'movie' => '电影',
  'episode' => '剧集',
  'audio' => '音频',
  _ => '视频',
};
