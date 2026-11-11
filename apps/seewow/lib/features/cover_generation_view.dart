import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../domain/media_item.dart';
import '../domain/metadata_language_draft.dart';
import '../metadata/cover_generator.dart';
import '../metadata/metadata_transport.dart';
import '../sources/native_bridge.dart';

Future<void> configureCoverGeneration(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const CoverGenerationSettings(),
);

class CoverGenerationSettings extends StatefulWidget {
  const CoverGenerationSettings({super.key});
  @override
  State<CoverGenerationSettings> createState() =>
      _CoverGenerationSettingsState();
}

class _CoverGenerationSettingsState extends State<CoverGenerationSettings> {
  final _endpoint = TextEditingController(),
      _model = TextEditingController(),
      _token = TextEditingController();
  String _size = '1024x1536';
  bool _base64 = false, _lan = false, _clear = false, _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    CoverGenerationConfig.load()
        .then((c) {
          if (mounted)
            setState(() {
              _endpoint.text = c.endpoint;
              _model.text = c.model;
              _size = c.size;
              _base64 = c.requestBase64;
              _lan = c.allowLan;
              _busy = false;
            });
        })
        .catchError((Object _) {
          if (mounted)
            setState(() {
              _busy = false;
              _error = '配置读取失败，可重新填写';
            });
        });
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CoverGenerationConfig(
        endpoint: _endpoint.text.trim(),
        model: _model.text.trim(),
        size: _size,
        requestBase64: _base64,
        allowLan: _lan,
      ).save(token: _token.text.trim(), clearToken: _clear);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException ? '${e.message}' : '配置保存失败',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('AI 封面服务'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '自行配置 Images API 兼容的本机或远程图像生成服务。仅在主动生成时发送你确认的封面描述；远程服务可能收费，费用与内容授权由所用服务决定。',
              ),
              TextField(
                controller: _endpoint,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '完整图像生成地址',
                  hintText: 'https://服务地址/v1/images/generations',
                ),
              ),
              TextField(
                controller: _model,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '图像模型名称'),
              ),
              TextField(
                controller: _token,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API 密钥（本机服务可留空）',
                  helperText: '留空保留同地址密钥；更改地址后需重新填写',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_size),
                initialValue: _size,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '生成尺寸'),
                items: [
                  for (final s in [
                    '1024x1536',
                    '1024x1024',
                    '1024x1792',
                    'auto',
                  ])
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _size = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _base64,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _base64 = v ?? false),
                title: const Text('请求 response_format: b64_json'),
                subtitle: const Text('模型默认返回 Base64 时关闭；仅返回 URL 的兼容服务可尝试开启'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _lan,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _lan = v ?? false),
                title: const Text('允许连接信任的局域网服务'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _clear,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _clear = v ?? false),
                title: const Text('清除该地址的已存密钥'),
              ),
              const Text(
                '仅接受 Base64 返回的 PNG／JPEG／WebP 图片；不下载接口返回的任意图片链接。公网须 HTTPS，本机支持 HTTP。不附带模型或预置密钥。',
              ),
              if (_error != null) Text(_error!),
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
          child: const Text('保存封面服务'),
        ),
      ],
    ),
  );
}

Future<void> generateMediaCover(
  BuildContext context,
  LibraryStore store,
  MediaItem item, {
  Future<CoverGenerator> Function()? generatorFactory,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => CoverGenerationDialog(
    store: store,
    item: store.current(item),
    generatorFactory: generatorFactory,
  ),
);

class CoverGenerationDialog extends StatefulWidget {
  const CoverGenerationDialog({
    super.key,
    required this.store,
    required this.item,
    this.generatorFactory,
  });
  final LibraryStore store;
  final MediaItem item;
  final Future<CoverGenerator> Function()? generatorFactory;
  @override
  State<CoverGenerationDialog> createState() => _CoverGenerationDialogState();
}

class _CoverGenerationDialogState extends State<CoverGenerationDialog> {
  late final _prompt = TextEditingController(
    text: CoverGenerator.initialPrompt(widget.item),
  );
  late final _before = metadataSnapshot(widget.item);
  CoverGenerator? _generator;
  GeneratedCover? _preview;
  String? _destination, _error;
  bool _busy = false, _saving = false, _replace = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _describeService();
  }

  Future<void> _describeService() async {
    try {
      final config = await CoverGenerationConfig.load();
      if (mounted)
        setState(() => _destination = Uri.tryParse(config.endpoint)?.host);
    } catch (_) {}
  }

  @override
  void dispose() {
    _revision++;
    _generator?.close();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
    });
    try {
      _checkCurrent();
      _generator?.close();
      final generator =
          await (widget.generatorFactory ??
              () async {
                final config = await CoverGenerationConfig.load();
                return CoverGenerator(
                  config,
                  token:
                      await NativeBridge.secretRead(config.credentialKey) ?? '',
                );
              })();
      if (!mounted || revision != _revision) {
        generator.close();
        throw MetadataCancelled();
      }
      _generator = generator;
      _checkCurrent();
      final cover = await generator.generate(widget.item, _prompt.text);
      if (revision != _revision) throw MetadataCancelled();
      if (mounted) setState(() => _preview = cover);
    } on MetadataCancelled {
      if (mounted) setState(() => _error = '已停止生成；远程服务可能已经计费');
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? '${e.message}'
              : '封面生成失败，请检查模型、接口或额度',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _checkCurrent() {
    final current = widget.store.items
        .where((i) => i.id == widget.item.id)
        .firstOrNull;
    if (current == null || metadataSnapshot(current) != _before)
      throw const FormatException('媒体资料或来源已改变，请关闭后重新打开');
    if (!current.aiAllowed) throw const FormatException('此来源不允许 AI 处理');
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.applyGeneratedCover(
        itemId: widget.item.id,
        before: _before,
        bytes: _preview!.bytes,
        model: _preview!.model,
        createdAt: _preview!.createdAt,
        replace: _replace,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException ? '${e.message}' : '封面保存失败，请重试',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_saving,
    child: AlertDialog(
      title: const Text('AI 生成封面'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '为缺少封面的个人媒体创建原创配图。生成图会标记为 AI 配图，不代表官方海报或作品事实。请使用你有权处理的内容与描述。',
              ),
              if (_destination?.isNotEmpty == true)
                Text('本次描述发送到：$_destination'),
              const Text('仅发送下方描述，不上传视频、截图、文件路径或片源凭据。生成可能产生服务费用；先预览再保存。'),
              TextButton(
                onPressed: _busy || _saving
                    ? null
                    : () async {
                        await configureCoverGeneration(context);
                        if (mounted) {
                          setState(() => _preview = null);
                          await _describeService();
                        }
                      },
                child: const Text('配置 AI 封面服务'),
              ),
              TextField(
                controller: _prompt,
                enabled: !_busy && !_saving,
                minLines: 4,
                maxLines: 9,
                onChanged: (_) => setState(() => _preview = null),
                decoration: const InputDecoration(
                  labelText: '确认发送的封面描述',
                  alignLabelWithHint: true,
                ),
              ),
              if (widget.item.posterUrl?.isNotEmpty == true &&
                  !widget.item.posterUrl!.startsWith('seewow:'))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _replace,
                  onChanged: _busy || _saving
                      ? null
                      : (v) => setState(() => _replace = v ?? false),
                  title: const Text('此条目已有封面，确认替换'),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || _saving || !widget.item.aiAllowed
                    ? null
                    : _generate,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(_preview == null ? '生成封面预览' : '重新生成（可能再次计费）'),
              ),
              if (!widget.item.aiAllowed) const Text('此来源已限制 AI，封面生成不可用。'),
              if (_busy || _saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_busy)
                TextButton(
                  onPressed: () {
                    _revision++;
                    _generator?.close();
                  },
                  child: const Text('停止生成'),
                ),
              if (_preview != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    height: 280,
                    child: Image.memory(_preview!.bytes, fit: BoxFit.contain),
                  ),
                ),
                Text('AI 配图 · ${_preview!.model} · 仅保存至 SeeWow 本机封面目录'),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy || _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy || _saving || _preview == null ? null : _save,
          child: const Text('保存封面'),
        ),
      ],
    ),
  );
}
