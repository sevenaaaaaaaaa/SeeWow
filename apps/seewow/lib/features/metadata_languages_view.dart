import 'package:flutter/material.dart';

import '../domain/media_metadata.dart';
import '../domain/metadata_languages.dart';
import '../metadata/local_metadata_translation.dart';

class MetadataLanguagePicker extends StatelessWidget {
  const MetadataLanguagePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final Set<String> value;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      for (final language in MetadataLanguage.regional)
        FilterChip(
          label: Text(
            language.name,
            locale: Locale(language.tag.split('-').first, language.region),
            style: TextStyle(fontFamily: MetadataLanguage.font(language.tag)),
          ),
          selected: value.contains(language.tag),
          onSelected: !enabled
              ? null
              : (selected) {
                  final next = {...value};
                  if (selected) {
                    next.add(language.tag);
                  } else {
                    next.remove(language.tag);
                  }
                  onChanged(next);
                },
        ),
    ],
  );
}

class MetadataLanguagesView extends StatefulWidget {
  const MetadataLanguagesView({
    super.key,
    required this.metadata,
    this.compact = false,
  });
  final MediaMetadata metadata;
  final bool compact;
  @override
  State<MetadataLanguagesView> createState() => _MetadataLanguagesViewState();
}

class _MetadataLanguagesViewState extends State<MetadataLanguagesView> {
  late Set<String> _selected;
  @override
  void initState() {
    super.initState();
    _selected = widget.metadata.preferredLanguages.isNotEmpty
        ? widget.metadata.preferredLanguages.toSet()
        : widget.metadata.localized.keys.take(8).toSet();
  }

  @override
  void didUpdateWidget(covariant MetadataLanguagesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.id != widget.metadata.id ||
        oldWidget.metadata.provider != widget.metadata.provider ||
        oldWidget.metadata.preferredLanguages.join(',') !=
            widget.metadata.preferredLanguages.join(',') ||
        (oldWidget.metadata.localized.isEmpty &&
            widget.metadata.localized.isNotEmpty)) {
      _selected = widget.metadata.preferredLanguages.isNotEmpty
          ? widget.metadata.preferredLanguages.toSet()
          : widget.metadata.localized.keys.take(8).toSet();
    }
  }

  String origin(String value) => switch (value) {
    'machine' => '本机机译 · 非官方译名',
    'manual' => '人工编辑',
    _ => '资料源译文',
  };
  @override
  Widget build(BuildContext context) {
    final metadata = widget.metadata;
    if (metadata.localized.isEmpty &&
        metadata.preferredLanguages.isEmpty &&
        metadata.alternativeTitles.isEmpty)
      return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('多语言资料 · ${metadata.localized.length} 个版本'),
      initiallyExpanded: !widget.compact,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('可同时选择多个版本。缺失内容留空，机器翻译单独标记；原始人员姓名保留。'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: MetadataLanguagePicker(
            value: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),
        ),
        if (metadata.localized.keys.any(
          (tag) => !MetadataLanguage.defaults.contains(tag),
        ))
          DropdownButton<String>(
            isExpanded: true,
            hint: const Text('添加其他已采集语言'),
            items: [
              for (final tag in metadata.localized.keys.where(
                (tag) =>
                    !MetadataLanguage.defaults.contains(tag) &&
                    !_selected.contains(tag),
              ))
                DropdownMenuItem(
                  value: tag,
                  child: Text('${MetadataLanguage.label(tag)} · $tag'),
                ),
            ],
            onChanged: (tag) {
              if (tag != null) setState(() => _selected.add(tag));
            },
          ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final tag in _selected)
                SizedBox(
                  width: box.maxWidth > 680
                      ? (box.maxWidth - 10) / 2
                      : box.maxWidth,
                  child: Builder(
                    builder: (context) {
                      final text = metadata.localized[tag];
                      final stale =
                          text?.machine == true &&
                          text!.inputHash !=
                              LocalMetadataTranslator.sourceHash(metadata);
                      final baseStyle = Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            fontFamily: MetadataLanguage.font(tag),
                            locale: Locale(
                              tag.split('-').first,
                              tag.contains('-') ? tag.split('-').last : null,
                            ),
                            height: tag.startsWith('bo') ? 1.9 : 1.6,
                          );
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${MetadataLanguage.label(tag)} · $tag',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontFamily: MetadataLanguage.font(tag),
                                    ),
                              ),
                              if (text == null || text.empty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text('暂无该语言资料，可在多语言管理中本机补译'),
                                )
                              else ...[
                                if (text.title.isNotEmpty) ...[
                                  Text(
                                    '标题 · ${origin(text.titleOrigin)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                  SelectableText(
                                    text.title,
                                    textDirection: MetadataLanguage.rtl(tag)
                                        ? TextDirection.rtl
                                        : TextDirection.ltr,
                                    textAlign: MetadataLanguage.rtl(tag)
                                        ? TextAlign.right
                                        : TextAlign.left,
                                    style: baseStyle,
                                  ),
                                ],
                                if (text.overview.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '简介 · ${origin(text.overviewOrigin)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                  Text(
                                    text.overview,
                                    textAlign: MetadataLanguage.rtl(tag)
                                        ? TextAlign.right
                                        : TextAlign.left,
                                    textDirection: MetadataLanguage.rtl(tag)
                                        ? TextDirection.rtl
                                        : TextDirection.ltr,
                                    style: baseStyle,
                                    maxLines: widget.compact ? 3 : 5,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  TextButton(
                                    onPressed: () => showDialog<void>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(
                                          '${MetadataLanguage.label(tag)} · 简介',
                                          style: TextStyle(
                                            fontFamily: MetadataLanguage.font(
                                              tag,
                                            ),
                                          ),
                                        ),
                                        content: SingleChildScrollView(
                                          child: SelectableText(
                                            text.overview,
                                            textAlign: MetadataLanguage.rtl(tag)
                                                ? TextAlign.right
                                                : TextAlign.left,
                                            textDirection:
                                                MetadataLanguage.rtl(tag)
                                                ? TextDirection.rtl
                                                : TextDirection.ltr,
                                            style: baseStyle,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('关闭'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    child: const Text('查看全文'),
                                  ),
                                ],
                                if (text.machine)
                                  Text(
                                    '模型：${text.engine} · 仅作参考',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                if (stale) const Text('原资料已变化，此机译可能过期；可重新补译'),
                                if (!stale && text.roles.isNotEmpty)
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: const Text('角色与职务译文'),
                                    children: [
                                      for (final entry in text.roles.entries)
                                        if (int.tryParse(entry.key) != null &&
                                            int.parse(entry.key) >= 0 &&
                                            int.parse(entry.key) <
                                                metadata.people.length)
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              metadata
                                                  .people[int.parse(entry.key)]
                                                  .name,
                                            ),
                                            subtitle: Text(
                                              entry.value,
                                              style: baseStyle,
                                              textDirection:
                                                  MetadataLanguage.rtl(tag)
                                                  ? TextDirection.rtl
                                                  : TextDirection.ltr,
                                            ),
                                          ),
                                    ],
                                  ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        if (metadata.alternativeTitles.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('资料源地区别名'),
            children: [
              for (final entry in metadata.alternativeTitles.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key),
                  subtitle: Text(entry.value.join(' / ')),
                ),
            ],
          ),
      ],
    );
  }
}
