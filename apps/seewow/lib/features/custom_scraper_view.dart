import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/artwork.dart';
import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import '../domain/metadata_language_draft.dart';
import '../metadata/custom_scraper.dart';
import '../metadata/metadata_transport.dart';
import 'metadata_facts.dart';

Future<void> configureCustomScrapers(
  BuildContext context, {
  CustomScraperRepository? repository,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => CustomScraperSettings(
    repository: repository ?? CustomScraperRepository(),
  ),
);

class CustomScraperSettings extends StatefulWidget {
  const CustomScraperSettings({super.key, required this.repository});
  final CustomScraperRepository repository;
  @override
  State<CustomScraperSettings> createState() => _CustomScraperSettingsState();
}

class _CustomScraperSettingsState extends State<CustomScraperSettings> {
  final _json = TextEditingController(), _token = TextEditingController();
  List<CustomScraperProfile> _profiles = [];
  CustomScraperProfile? _selected;
  String? _error;
  bool _busy = true, _clear = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _profiles = list;
        _edit(list.firstOrNull);
      });
    } catch (_) {
      if (mounted) setState(() => _error = '读取配置失败，请检查本机凭据存储');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(CustomScraperProfile? profile) {
    _selected = profile;
    _json.text = const JsonEncoder.withIndent('  ')
        .convert((profile ?? CustomScraperProfile.example).toJson());
    _token.clear();
    _clear = false;
    _error = null;
  }

  @override
  void dispose() {
    _json.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_json.text.length > 32768) throw const FormatException('配置超过 32 KiB');
      final profile = CustomScraperProfile.fromJson(
        jsonDecode(_json.text) as Map<String, dynamic>,
      );
      await widget.repository.save(
        profile,
        token: _token.text.trim(),
        clearToken: _clear,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException && e.source == null
              ? '${e.message}'
              : 'JSON 配置格式或字段类型有误，请检查后重试',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_selected == null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.remove(_selected!);
      await _load();
    } catch (_) {
      if (mounted)
        setState(() {
          _error = '移除失败，请重试';
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('自定义刮削 API'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '连接你有权使用的影视资料 API。仅搜索并读取 JSON 元数据，不执行脚本或播放解析规则。请确认资料、图片的使用与商用授权；保存配置不代表服务已获授权。',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selected?.id,
                key: ValueKey(_selected?.id),
                isExpanded: true,
                decoration: const InputDecoration(labelText: '已保存的适配'),
                items: [
                  for (final p in _profiles)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(
                        () => _edit(_profiles.firstWhere((p) => p.id == id)),
                      ),
              ),
              Wrap(
                spacing: 10,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _edit(null)),
                    child: const Text('新建适配'),
                  ),
                  if (_selected != null)
                    TextButton(
                      onPressed: _busy ? null : _delete,
                      child: const Text('移除此适配'),
                    ),
                ],
              ),
              TextField(
                controller: _json,
                enabled: !_busy,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'JSON 适配配置',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'kinds：movie／episode／other；category 可填写动画、课程等自定义类型。searchQuery 支持 {query}、{kind}、{category}、{language}、{year}、{season}、{episode}。fields 使用点分隔的 JSON 路径；详情可选 detailsPath（含 {id}）。',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'API 密钥（可选）',
                  helperText: '留空保留同一服务的密钥；更改地址后需重新填写',
                  helperMaxLines: 3,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _clear,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _clear = v ?? false),
                title: const Text('清除当前服务的已存密钥'),
              ),
              const Text(
                '公网接口使用 HTTPS。NAS／局域网接口需将 allowLan 设为 true。请求只发送搜索词、类型、语言、年份与季集，不发送媒体路径或片源凭据。',
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存适配'),
        ),
      ],
    ),
  );
}

Future<void> matchCustomMetadata(
  BuildContext context,
  LibraryStore store,
  MediaItem item, {
  CustomScraperRepository? repository,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => CustomScraperMatch(
    store: store,
    item: store.current(item),
    repository: repository ?? CustomScraperRepository(),
  ),
);

class CustomScraperMatch extends StatefulWidget {
  const CustomScraperMatch({
    super.key,
    required this.store,
    required this.item,
    required this.repository,
  });
  final LibraryStore store;
  final MediaItem item;
  final CustomScraperRepository repository;
  @override
  State<CustomScraperMatch> createState() => _CustomScraperMatchState();
}

class _CustomScraperMatchState extends State<CustomScraperMatch> {
  late final _query = TextEditingController(text: widget.item.title);
  final _language = TextEditingController(text: 'zh-CN');
  late final _before = metadataSnapshot(widget.item);
  List<CustomScraperProfile> _profiles = [];
  CustomScraperProfile? _profile;
  CustomScraperClient? _client;
  List<MediaMetadata> _results = [];
  MediaMetadata? _preview;
  String? _error;
  bool _busy = false,
      _replace = false,
      _loading = true,
      _searched = false,
      _saving = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.repository.load();
      if (mounted)
        setState(() {
          _profiles = list
              .where((p) => p.kinds.contains(widget.item.kind.name))
              .toList();
          _profile = _profiles.firstOrNull;
        });
    } catch (_) {
      if (mounted) setState(() => _error = '读取 API 配置失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _revision++;
    _client?.close();
    _query.dispose();
    _language.dispose();
    super.dispose();
  }

  void _invalidate() => setState(() {
    _preview = null;
    _results = [];
    _searched = false;
    _error = null;
  });
  Future<void> _search() async {
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
      _results = [];
    });
    try {
      _client?.close();
      final client = await widget.repository.client(_profile!);
      if (!mounted || revision != _revision) {
        client.close();
        throw MetadataCancelled();
      }
      _client = client;
      final results = await client.search(
        widget.item,
        _query.text,
        language: _language.text.trim(),
      );
      if (revision != _revision) throw MetadataCancelled();
      if (mounted)
        setState(() {
          _results = results;
          _searched = true;
        });
    } on MetadataCancelled {
      if (mounted) setState(() => _error = '查询已停止');
    } catch (e) {
      if (mounted)
        setState(
          () =>
              _error = e is FormatException ? '${e.message}' : '查询失败，请检查适配与服务',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(MediaMetadata value) async {
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
    });
    try {
      final preview = await _client!.details(value, widget.item);
      if (revision != _revision) throw MetadataCancelled();
      if (mounted) setState(() => _preview = preview);
    } on MetadataCancelled {
      if (mounted) setState(() => _error = '预览已停止');
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException ? '${e.message}' : '详情格式或字段映射无效',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _saving = true;
      _error = null;
    });
    try {
      if (metadataSnapshot(widget.store.current(widget.item)) != _before)
        throw const FormatException('媒体资料已改变，请关闭后重新匹配');
      await widget.store.applyMetadata(
        widget.item.id,
        _preview!.withArtwork(_replace),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException ? '${e.message}' : '保存失败，请重试',
        );
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('自定义 API 匹配'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('搜索 → 选择结果 → 预览 → 确认。仅修改当前条目的本机资料，保留媒体文件与观看进度。'),
              if (_loading) const LinearProgressIndicator(),
              if (!_loading && _profiles.isEmpty)
                const Text('暂无适用于此视频类型的 API，请先添加适配。'),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await configureCustomScrapers(
                          context,
                          repository: widget.repository,
                        );
                        if (mounted) {
                          _invalidate();
                          await _load();
                        }
                      },
                child: const Text('管理自定义 API'),
              ),
              if (_profile != null) ...[
                DropdownButtonFormField<String>(
                  initialValue: _profile!.id,
                  key: ValueKey(_profile!.id),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '资料服务与视频类型'),
                  items: [
                    for (final p in _profiles)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          '${p.name}${p.category.isEmpty ? '' : ' · ${p.category}'}',
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) {
                          _invalidate();
                          setState(
                            () => _profile = _profiles.firstWhere(
                              (p) => p.id == id,
                            ),
                          );
                        },
                ),
                TextField(
                  controller: _query,
                  enabled: !_busy,
                  onChanged: (_) => _invalidate(),
                  decoration: const InputDecoration(labelText: '搜索词'),
                ),
                TextField(
                  controller: _language,
                  enabled: !_busy,
                  onChanged: (_) => _invalidate(),
                  decoration: const InputDecoration(labelText: '资料语言'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _search,
                  child: const Text('搜索资料'),
                ),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_busy && !_saving)
                TextButton(
                  onPressed: () {
                    _revision++;
                    _client?.close();
                  },
                  child: const Text('停止请求'),
                ),
              if (_searched && _results.isEmpty)
                const Text('未找到匹配资料，可调整搜索词或服务。'),
              for (final c in _results)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.title),
                  subtitle: Text('${c.year ?? ''} · ${c.originalTitle}'),
                  selected: identical(c, _preview),
                  onTap: _busy ? null : () => _select(c),
                ),
              if (_preview != null) ...[
                const Divider(),
                Text(
                  '预览：${_preview!.title}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_preview!.posterUrl != null)
                  SizedBox(
                    height: 220,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: WowArt(url: _preview!.posterUrl),
                    ),
                  ),
                Text(_preview!.overview),
                MetadataFacts(metadata: _preview!, compact: true),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _replace,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _replace = v ?? false),
                  title: const Text('替换已有封面和背景图'),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy || _preview == null ? null : _save,
          child: const Text('确认当前条目'),
        ),
      ],
    ),
  );
}
