import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import '../domain/metadata_language_draft.dart';
import '../domain/metadata_languages.dart';
import '../metadata/local_metadata_translation.dart';
import '../metadata/tmdb_client.dart';
import 'metadata_languages_view.dart';

Future<void> manageMetadataLanguages(
  BuildContext context,
  LibraryStore store,
  List<MediaItem> items, {
  Future<TmdbClient> Function()? tmdbFactory,
  LocalMetadataTranslator Function(LocalTranslationConfig)? translatorFactory,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => MetadataLanguageBatch(
    store: store,
    items: items,
    tmdbFactory: tmdbFactory,
    translatorFactory: translatorFactory,
  ),
);

class MetadataLanguageBatch extends StatefulWidget {
  const MetadataLanguageBatch({
    super.key,
    required this.store,
    required this.items,
    this.tmdbFactory,
    this.translatorFactory,
  });
  final LibraryStore store;
  final List<MediaItem> items;
  final Future<TmdbClient> Function()? tmdbFactory;
  final LocalMetadataTranslator Function(LocalTranslationConfig)?
  translatorFactory;
  @override
  State<MetadataLanguageBatch> createState() => _MetadataLanguageBatchState();
}

class _MetadataLanguageBatchState extends State<MetadataLanguageBatch> {
  final _endpoint = TextEditingController(
        text: 'http://127.0.0.1:11434/v1/chat/completions',
      ),
      _model = TextEditingController();
  final _drafts = <String, MetadataLanguageDraft>{};
  final _errors = <String, String>{};
  final _toSave = <String>{};
  Set<String> _languages = MetadataLanguage.defaults.toSet();
  late final List<MediaItem> _items;
  TmdbClient? _tmdb;
  LocalMetadataTranslator? _translator;
  bool _busy = false, _stopped = false, _configEdited = false;
  String? _message;
  int _done = 0;
  @override
  void initState() {
    super.initState();
    _items = widget.items.map(widget.store.current).toList();
    LocalTranslationConfig.load().then((config) {
      if (mounted && !_configEdited)
        setState(() {
          _endpoint.text = config.endpoint;
          _model.text = config.model;
        });
    });
  }

  @override
  void dispose() {
    _tmdb?.close();
    _translator?.close();
    _endpoint.dispose();
    _model.dispose();
    super.dispose();
  }

  LocalTranslationConfig get _config => LocalTranslationConfig(
    endpoint: _endpoint.text.trim(),
    model: _model.text.trim(),
  );
  void _stop() {
    _stopped = true;
    _translator?.cancel();
    _tmdb?.close();
    if (mounted) setState(() => _message = '正在停止，已完成预览仍可选择保存');
  }

  Future<void> _run(bool translate) async {
    if (_items.isEmpty || _items.length > 20 || _languages.isEmpty) {
      setState(() => _message = '每批选择 1 至 20 项，并选择至少一种语言');
      return;
    }
    setState(() {
      _busy = true;
      _stopped = false;
      _done = 0;
      _message = null;
      _errors.clear();
    });
    try {
      if (translate) {
        _config.validate();
        _translator?.close();
        _translator = (widget.translatorFactory ?? LocalMetadataTranslator.new)(
          _config,
        );
      } else {
        _tmdb?.close();
        _tmdb = await (widget.tmdbFactory ?? TmdbClient.configured)();
      }
      for (final item in _items) {
        if (!mounted || _stopped) break;
        final existing = _drafts[item.id];
        var metadata = existing?.metadata ?? metadataForLanguages(item);
        var changed = false, generated = existing?.generatedByModel ?? false;
        try {
          if (translate) {
            if (!item.aiAllowed)
              throw const FormatException('此来源不允许 AI 处理，未发送到模型');
            final texts = {...metadata.localized};
            for (final target in _languages) {
              if (_stopped) break;
              if (!LocalMetadataTranslator.needsTranslation(metadata, target))
                continue;
              if (mounted)
                setState(
                  () => _message =
                      '正在补译：${item.displayTitle} · ${MetadataLanguage.label(target)}',
                );
              try {
                texts[target] = await _translator!.translate(
                  item,
                  metadata,
                  target,
                );
                changed = true;
                generated = true;
              } on TranslationCancelled {
                break;
              } catch (e) {
                _errors[item.id] =
                    '${_errors[item.id] ?? ''}${MetadataLanguage.label(target)}：${e is FormatException ? e.message : '本机翻译失败'}\n';
              }
            }
            metadata = metadata.withLanguages(
              texts,
              preferred: _languages.toList(),
            );
          } else {
            final id = metadata.provider == 'tmdb'
                ? metadata.id
                : int.tryParse(metadata.externalIds['tmdb'] ?? '') ?? 0;
            if (id <= 0)
              throw const FormatException('缺少已确认的 TMDB ID；可先匹配资料，或直接补译现有文字');
            final canonical = MediaMetadata.fromJson({
              ...metadata.toJson(),
              'id': id,
            });
            _tmdb!.locale = MetadataLocale(
              language: _tmdb!.locale.language,
              additionalLanguages: _languages.toList(),
            );
            final collected = await _tmdb!.collectTranslations(
              canonical,
              seriesId: int.tryParse(metadata.externalIds['tmdb_series'] ?? ''),
              season: item.season,
              episode: item.episode,
            );
            metadata = metadata.withLanguages(
              collected.localized,
              preferred: _languages.toList(),
            );
            changed = true;
          }
          if (changed) {
            _drafts[item.id] = MetadataLanguageDraft(
              itemId: item.id,
              before: existing?.before ?? metadataSnapshot(item),
              metadata: metadata,
              generatedByModel: generated,
            );
            _toSave.add(item.id);
          }
        } catch (e) {
          if (!_stopped)
            _errors[item.id] = e is FormatException
                ? e.message.toString()
                : '资料采集失败，请检查网络、ID 与配置';
        }
        if (mounted)
          setState(() {
            _done++;
          });
      }
      if (mounted)
        setState(
          () => _message = _stopped
              ? '已停止，只有下方成功预览可保存'
              : '预览完成，请检查译文后再保存。未生成的语言不会用其他语言冒充',
        );
    } catch (e) {
      if (mounted)
        setState(
          () => _message = e is FormatException
              ? e.message.toString()
              : '服务不可用，请检查本机模型或资料源配置',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.store.applyLanguageDrafts([
        for (final id in _toSave) _drafts[id]!,
      ]);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _message = e is FormatException
              ? e.message.toString()
              : '保存失败，资料未确认写入',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('多语言资料 · ${_items.length} 项'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '采集已匹配作品的现有译文，或用本机模型补译缺失／过期的标题和简介。仅处理所选条目，保存前不修改片库。人员姓名、评分与播放地址不翻译。',
              ),
              const SizedBox(height: 12),
              MetadataLanguagePicker(
                value: _languages,
                enabled: !_busy,
                onChanged: (v) => setState(() => _languages = v),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('本机翻译模型设置'),
                children: [
                  const Text(
                    '连接已启动的本机 Chat Completions 服务，例如 Ollama / LM Studio。本应用不下载模型、不回退云端；请在服务中选择离线模型。藏文等译文质量取决于模型，需人工校对。',
                  ),
                  TextField(
                    controller: _endpoint,
                    enabled: !_busy,
                    onChanged: (_) => _configEdited = true,
                    decoration: const InputDecoration(labelText: '本机翻译地址'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _model,
                    enabled: !_busy,
                    onChanged: (_) => _configEdited = true,
                    decoration: const InputDecoration(labelText: '已安装的本地模型名称'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            try {
                              await _config.save();
                              if (mounted) setState(() => _message = '本机设置已保存');
                            } catch (e) {
                              if (mounted)
                                setState(
                                  () => _message = e is FormatException
                                      ? e.message.toString()
                                      : '设置保存失败',
                                );
                            }
                          },
                    child: const Text('保存本机设置'),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(false),
                    icon: const Icon(Icons.language),
                    label: const Text('采集现有文字译文'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(true),
                    icon: const Icon(Icons.translate),
                    label: const Text('本机补译缺失／过期文字'),
                  ),
                ],
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(
                    value: _items.isEmpty ? null : _done / _items.length,
                  ),
                ),
              if (_busy) Text('已处理 $_done / ${_items.length} 项'),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!),
                ),
              for (final item in _items) ...[
                if (_errors.containsKey(item.id))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${item.displayTitle}：${_errors[item.id]}'),
                  ),
                if (_drafts.containsKey(item.id)) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _toSave.contains(item.id),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              _toSave.add(item.id);
                            } else {
                              _toSave.remove(item.id);
                            }
                          }),
                    title: Text(item.displayTitle),
                    subtitle: const Text('勾选后随本次预览保存，主标题与原文件保持原样'),
                  ),
                  MetadataLanguagesView(
                    key: ValueKey(
                      '${item.id}-${_drafts[item.id]!.metadata.localized.length}',
                    ),
                    metadata: _drafts[item.id]!.metadata,
                    compact: true,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_busy)
          TextButton(onPressed: _stop, child: const Text('停止'))
        else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        FilledButton(
          onPressed: _busy || _toSave.isEmpty ? null : _save,
          child: Text('保存所选预览（${_toSave.length}）'),
        ),
      ],
    ),
  );
}
