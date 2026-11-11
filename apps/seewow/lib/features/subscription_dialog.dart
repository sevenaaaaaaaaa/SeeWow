import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/iptv_store.dart';
import '../domain/subscription.dart';

Future<bool> importSubscription(
  BuildContext context,
  IPTVStore store, {
  String initial = '',
  String name = '',
  String epgUrl = '',
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SubscriptionDialog(
        store: store,
        initial: initial,
        name: name,
        epgUrl: epgUrl,
      ),
    ) ??
    false;

class SubscriptionDialog extends StatefulWidget {
  const SubscriptionDialog({
    super.key,
    required this.store,
    this.initial = '',
    this.name = '',
    this.epgUrl = '',
  });
  final IPTVStore store;
  final String initial, name, epgUrl;
  @override
  State<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<SubscriptionDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _source, _name, _epg;
  SubscriptionPreview? _preview;
  final _history = <SubscriptionPreview>[];
  String? _error, _readSource;
  bool _busy = false, _allowLan = false;

  @override
  void initState() {
    super.initState();
    _source = TextEditingController(text: widget.initial);
    _name = TextEditingController(text: widget.name);
    _epg = TextEditingController(text: widget.epgUrl);
  }

  @override
  void dispose() {
    _source.dispose();
    _name.dispose();
    _epg.dispose();
    super.dispose();
  }

  void _invalidate() {
    setState(() {
      _preview = null;
      _history.clear();
      _readSource = null;
      _error = null;
    });
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8', 'txt', 'json'],
      );
      if (!mounted || result == null) return;
      final path = result.path;
      if (path == null) {
        setState(() => _error = '请先将文件保存到设备，再选择本地文件');
        return;
      }
      _source.text = path;
      _invalidate();
    } catch (_) {
      if (mounted) setState(() => _error = '无法选择文件，请检查文件访问权限');
    }
  }

  Future<void> _read({SubscriptionLink? link}) async {
    if (link == null && !_form.currentState!.validate()) return;
    if (link != null &&
        (_history.length >= 5 ||
            [?_preview, ..._history].any((p) => p.uri == link.uri))) {
      setState(() => _error = '配置循环引用或层级过多，请直接导入所需列表');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = link?.uri.toString() ?? _source.text.trim();
      final data = await widget.store.preview(
        target,
        allowLocalNetwork: _allowLan,
      );
      if (!mounted) return;
      if (link != null &&
          [?_preview, ..._history].any((p) => p.uri == data.uri)) {
        throw const FormatException('配置重定向形成循环，请直接导入所需列表');
      }
      setState(() {
        if (link != null && _preview != null) _history.add(_preview!);
        _preview = data;
        _readSource = target;
        if (link != null) _source.text = target;
        if (link != null) _name.text = link.name;
        if (widget.epgUrl.isEmpty || link != null)
          _epg.text = data.epgUrl ?? link?.epgUrl ?? '';
      });
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : '读取失败，请检查地址、文件格式或访问权限',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_preview == null || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.store.importPreview(
      _preview!,
      name: _name.text,
      source: _readSource,
      epgUrl: _epg.text,
      allowLocalNetwork: _allowLan,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = widget.store.toast ?? '导入失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _preview;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('导入播放列表'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('导入你有权使用的媒体列表。先预览，再确认导入；配置中的爬虫和解析插件不受支持。'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _source,
                    enabled: !_busy,
                    onChanged: (_) => _invalidate(),
                    decoration: const InputDecoration(
                      labelText: '列表地址或本地文件',
                      hintText: 'HTTP(S) 地址，或选择本地文件',
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请填写地址或选择本地文件' : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('选择本地文件'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowLan,
                    onChanged: _busy
                        ? null
                        : (v) {
                            _allowLan = v ?? false;
                            _invalidate();
                          },
                    title: const Text('允许此订阅访问局域网'),
                    subtitle: const Text('仅在信任该列表且需要连接家庭网络时开启'),
                  ),
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: '显示名称（可选）'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _epg,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'XMLTV 节目单地址（可选）',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final u = Uri.tryParse(v.trim());
                      return u != null &&
                              ['http', 'https'].contains(u.scheme) &&
                              u.host.isNotEmpty &&
                              u.userInfo.isEmpty
                          ? null
                          : '请填写不含内嵌账号密码的 HTTP(S) 地址';
                    },
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (data != null) ...[
                    const Divider(height: 28),
                    Text(
                      '预览：${data.channels.length} 个频道 · ${data.links.length} 个配置',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (_history.isNotEmpty)
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _preview = _history.removeLast();
                                  _readSource = _preview!.uri.toString();
                                  _source.text = _readSource!;
                                  _epg.text = _preview!.epgUrl ?? '';
                                  _error = null;
                                });
                              },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('返回上级配置'),
                      ),
                    for (final warning in data.warnings)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(warning),
                      ),
                    if (data.links.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('选择一个配置继续预览；不会批量订阅其他配置。'),
                      ),
                    for (final link in data.links.take(100))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(link.name),
                        subtitle: Text(link.uri.host),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => _read(link: link),
                      ),
                    if (data.links.length > 100)
                      const Text('仅展示前 100 个配置，请使用更小的配置目录。'),
                    for (final channel in data.channels.take(12))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(channel.name),
                        subtitle: Text(channel.group),
                      ),
                    if (data.channels.length > 12)
                      Text('另有 ${data.channels.length - 12} 个频道，确认后一起导入'),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          if (data == null)
            FilledButton(
              onPressed: _busy ? null : () => _read(),
              child: const Text('读取预览'),
            )
          else
            FilledButton(
              onPressed: _busy || data.channels.isEmpty || widget.store.loading
                  ? null
                  : _import,
              child: const Text('确认导入频道'),
            ),
        ],
      ),
    );
  }
}
