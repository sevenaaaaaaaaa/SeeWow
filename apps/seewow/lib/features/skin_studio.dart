import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent/agent_controller.dart';
import '../design/cinema_widgets.dart';
import '../design/skin.dart';
import '../design/skin_generator.dart';
import '../design/skin_spec.dart';
import '../design/tokens.dart';

class SkinStudio extends StatelessWidget {
  const SkinStudio({super.key, this.agent});
  final AgentController? agent;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: WowSkin.I,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('外观与皮肤', subtitle: '让界面退后，让电影向前。'),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final spec in builtInSkins)
                SizedBox(
                  width: box.maxWidth < 580
                      ? box.maxWidth
                      : (box.maxWidth - 28) / 3,
                  child: _PresetCard(spec: spec),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _open(context, 0),
              icon: const Icon(Icons.tune, size: 17),
              label: const Text('自定义当前皮肤'),
            ),
            OutlinedButton.icon(
              onPressed: () => _open(context, 1),
              icon: const Icon(Icons.extension_outlined, size: 17),
              label: const Text('社区皮肤'),
            ),
            OutlinedButton.icon(
              onPressed: () => _open(context, 2),
              icon: const Icon(Icons.auto_awesome_outlined, size: 17),
              label: const Text('从 design.md 生成'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '当前：${WowSkin.I.spec.name} · ${WowSkin.I.isLight ? '浅色' : '深色'} · ${WowSkin.I.isGlass ? '玻璃材质' : '纯色材质'}',
          style: WowType.body(12, color: WowColors.muted),
        ),
      ],
    ),
  );
  void _open(BuildContext context, int tab) => showDialog<void>(
    context: context,
    builder: (_) => SkinStudioDialog(initialTab: tab, agent: agent),
  );
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.spec});
  final SkinSpec spec;
  @override
  Widget build(BuildContext context) {
    final selected = WowSkin.I.spec.encode() == spec.encode();
    return Semantics(
      selected: selected,
      button: true,
      label: '${spec.name}主题',
      child: Material(
        color: WowColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? WowColors.accent : WowColors.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => WowSkin.I.use(spec),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkinPreview(spec: spec, miniature: true),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spec.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      size: 17,
                      color: selected ? WowColors.accent : WowColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  spec.description,
                  style: WowType.body(11, color: WowColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SkinPreview extends StatelessWidget {
  const SkinPreview({super.key, required this.spec, this.miniature = false});
  final SkinSpec spec;
  final bool miniature;
  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(
      fontFamily:
          wowVoices[WowFontId.values.firstWhere((v) => v.name == spec.font)]!
              .display,
      fontFamilyFallback:
          wowVoices[WowFontId.values.firstWhere((v) => v.name == spec.font)]!
              .fallback,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: miniature ? 124 : 240,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: spec.color('background'),
            gradient: spec.glass
                ? LinearGradient(
                    colors: [
                      spec.color('background'),
                      Color.alphaBlend(
                        spec.color('ambient').withValues(alpha: .4),
                        spec.color('background'),
                      ),
                    ],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  )
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: miniature ? 30 : 54,
                color: spec
                    .color('shell')
                    .withValues(alpha: spec.glass ? spec.opacity : 1),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Icon(
                      Icons.play_circle_outline,
                      size: miniature ? 14 : 22,
                      color: spec.color('accent'),
                    ),
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: Icon(
                          [
                            Icons.home_outlined,
                            Icons.video_library_outlined,
                            Icons.auto_awesome_outlined,
                          ][i],
                          size: miniature ? 11 : 16,
                          color: spec.color('muted'),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(miniature ? 12 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        miniature ? '你的私人影院' : '下一部，值得期待。',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: spec.color('text'),
                          fontSize: miniature ? 10 : 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (!miniature)
                        Text(
                          '为你放映  ·  继续观看  ·  我的片单',
                          style: TextStyle(
                            color: spec.color('muted'),
                            fontSize: 11,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Row(
                          children: [
                            for (var i = 0; i < 3; i++)
                              Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(right: i < 2 ? 7 : 0),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      spec.posterRadius.clamp(0, 12),
                                    ),
                                    color: spec
                                        .color('panel')
                                        .withValues(
                                          alpha: spec.glass ? spec.opacity : 1,
                                        ),
                                    border: Border.all(
                                      color: spec.color('line'),
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.local_movies_outlined,
                                      size: miniature ? 14 : 28,
                                      color: spec.color('muted'),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!miniature) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: spec.color('accent'),
                            borderRadius: BorderRadius.circular(
                              spec.radius.clamp(0, 10),
                            ),
                          ),
                          child: Text(
                            '开始观看',
                            style: TextStyle(
                              color: spec.onAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SkinStudioDialog extends StatefulWidget {
  const SkinStudioDialog({super.key, this.initialTab = 0, this.agent});
  final int initialTab;
  final AgentController? agent;
  @override
  State<SkinStudioDialog> createState() => _SkinStudioDialogState();
}

class _SkinStudioDialogState extends State<SkinStudioDialog> {
  late int _tab = widget.initialTab;
  late SkinSpec _draft = WowSkin.I.spec;
  late final TextEditingController _document = TextEditingController();
  String? _error, _notice;
  bool _busy = false;
  @override
  void dispose() {
    _document.dispose();
    super.dispose();
  }

  void _preview(SkinSpec spec) => setState(() {
    _draft = spec;
    _error = null;
    _notice = '预览已更新，应用后才会改变全局外观。';
  });
  void _edit(Map<String, dynamic> values) {
    try {
      _preview(_draft.edit(values));
    } catch (e) {
      setState(() => _error = _message(e));
    }
  }

  String _message(Object e) => e is FormatException ? e.message : '无法完成操作：$e';
  Future<void> _read() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'md'],
      );
      if (result.isEmpty || !mounted) return;
      final file = result.single;
      if ((await file.length() ?? 65537) > 65536)
        throw const FormatException('文件不能超过 64 KB');
      final contents = utf8.decode(await file.readAsBytes());
      if (mounted)
        setState(() {
          _document.text = contents;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<void> _generate({bool ai = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final spec = ai
          ? await SkinGenerator.generate(
              _document.text,
              endpoint: widget.agent!.endpoint,
              model: widget.agent!.model,
            )
          : (_tab == 1
                ? SkinSpec.decode(_document.text)
                : SkinSpec.fromDesign(_document.text));
      if (mounted) _preview(spec);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export({bool design = false}) async {
    try {
      final content = design ? skinDesignTemplate : _draft.encode();
      final path = await FilePicker.saveFile(
        dialogTitle: design ? '保存 design.md 模板' : '导出皮肤',
        fileName: design ? 'design.md' : 'seewow-skin.json',
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (path != null && mounted) setState(() => _notice = '文件已保存。');
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('皮肤工作室')),
          if (_busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: 900,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < 3; i++)
                      ChoiceChip(
                        label: Text(['自定义', '社区皮肤', 'design.md 生成'][i]),
                        selected: _tab == i,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() {
                                _tab = i;
                                _error = null;
                                _notice = null;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (box.maxWidth >= 720)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _controls()),
                      const SizedBox(width: 24),
                      SizedBox(width: 300, child: _previewPane()),
                    ],
                  )
                else ...[
                  _previewPane(),
                  const SizedBox(height: 20),
                  _controls(),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      _error!,
                      style: TextStyle(color: WowColors.error, fontSize: 12),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      _notice!,
                      style: TextStyle(color: WowColors.muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  WowSkin.I.use(_draft, install: true);
                  Navigator.pop(context);
                },
          child: const Text('应用并保存'),
        ),
      ],
    ),
  );

  Widget _previewPane() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SkinPreview(spec: _draft),
      const SizedBox(height: 14),
      Text(_draft.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 5),
      Text(
        '${_draft.author} · ${_draft.light ? '浅色' : '深色'}',
        style: WowType.body(11, color: WowColors.muted),
      ),
      const SizedBox(height: 8),
      Text(
        '预览为界面示意；影片画面保留原色。',
        style: WowType.body(11, color: WowColors.muted),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: _busy ? null : () => _export(),
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('导出 JSON'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: _draft.encode()),
                    );
                    if (mounted) setState(() => _notice = '皮肤 JSON 已复制。');
                  },
            child: const Text('复制'),
          ),
        ],
      ),
    ],
  );

  Widget _controls() => switch (_tab) {
    0 => _editor(),
    1 => _community(),
    _ => _design(),
  };
  Widget _editor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        key: ValueKey('name-${_draft.name}'),
        initialValue: _draft.name,
        decoration: const InputDecoration(labelText: '皮肤名称'),
        onFieldSubmitted: (v) => _edit({'name': v}),
        onChanged: (v) {
          if (v.trim().isNotEmpty && v.length <= 60)
            _draft = _draft.edit({'name': v});
        },
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final spec in builtInSkins)
            ActionChip(
              label: Text('以${spec.name}为基础'),
              onPressed: () => _preview(spec.edit({'name': '我的${spec.name}'})),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text('颜色', style: WowType.body(12, color: WowColors.muted)),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final role in SkinSpec.roles)
              SizedBox(
                width: (box.maxWidth - 10) / 2,
                child: TextFormField(
                  key: ValueKey('$role-${_draft.data['colors'][role]}'),
                  initialValue: _draft.data['colors'][role] as String,
                  decoration: InputDecoration(
                    labelText: {
                      'background': '画布',
                      'shell': '导航',
                      'panel': '面板',
                      'text': '正文',
                      'muted': '次级文字',
                      'faint': '弱化文字',
                      'accent': '强调色',
                      'line': '边框',
                      'ambient': '环境光',
                      'success': '成功',
                      'error': '错误',
                    }[role],
                    prefixIcon: Icon(
                      Icons.circle,
                      size: 13,
                      color: _draft.color(role),
                    ),
                  ),
                  onFieldSubmitted: (v) => _edit({
                    'colors': {..._draft.data['colors'] as Map, role: v.trim()},
                  }),
                  onChanged: (v) {
                    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v.trim()))
                      _edit({
                        'colors': {
                          ..._draft.data['colors'] as Map,
                          role: v.trim(),
                        },
                      });
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final font in WowFontId.values)
            ChoiceChip(
              label: Text(wowFontLabel(font)),
              selected: _draft.font == font.name,
              onSelected: (_) => _edit({'font': font.name}),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('玻璃材质', style: TextStyle(fontSize: 13)),
        value: _draft.glass,
        onChanged: (v) => _edit({'material': v ? 'glass' : 'flat'}),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('紧凑布局', style: TextStyle(fontSize: 13)),
        value: _draft.compact,
        onChanged: (v) => _edit({'density': v ? 'compact' : 'comfortable'}),
      ),
      _slider('面板圆角', 'radius', _draft.radius, 0, 28),
      _slider('海报圆角', 'posterRadius', _draft.posterRadius, 0, 24),
      if (_draft.glass) ...[
        _slider('模糊半径', 'blur', _draft.blur, 0, 40),
        _slider('面板不透明度', 'opacity', _draft.opacity, .65, .98),
      ],
    ],
  );
  Widget _slider(
    String label,
    String key,
    double value,
    double min,
    double max,
  ) => Row(
    children: [
      SizedBox(
        width: 100,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          onChanged: (v) => _edit({key: v}),
        ),
      ),
      SizedBox(
        width: 32,
        child: Text(
          key == 'opacity' ? '${(value * 100).round()}%' : '${value.round()}',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    ],
  );
  Widget _community() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '导入作者分享的 JSON / design.md，预览后应用。皮肤只包含样式参数。这里提供开放格式示例，尚未连接在线社区市场。',
        style: WowType.body(12, color: WowColors.muted),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final spec in communityExamples)
            ActionChip(
              label: Text('${spec.name} · 示例'),
              onPressed: () => _preview(spec),
            ),
        ],
      ),
      if (WowSkin.I.installed.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text('已保存', style: TextStyle(fontSize: 12)),
        for (final spec in WowSkin.I.installed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(spec.name, style: const TextStyle(fontSize: 13)),
            subtitle: Text(spec.author, style: const TextStyle(fontSize: 11)),
            onTap: () => _preview(spec),
            trailing: IconButton(
              tooltip: '移除已保存皮肤',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () {
                WowSkin.I.removeInstalled(spec.name);
                setState(() {});
              },
            ),
          ),
      ],
      const SizedBox(height: 16),
      _documentField('粘贴皮肤 JSON 或含皮肤代码块的 Markdown'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _read,
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('选择文件'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _generate(),
            child: const Text('校验并预览'),
          ),
        ],
      ),
    ],
  );
  Widget _design() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '提供设计意图、配色、字体和材质。规范参数可在本地生成；自由描述可交给你的 AI 模型。',
        style: WowType.body(12, color: WowColors.muted),
      ),
      const SizedBox(height: 12),
      _documentField('粘贴 design.md 内容'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _read,
            child: const Text('选择 design.md'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _document.text = skinDesignTemplate),
            child: const Text('载入模板'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _export(design: true),
            child: const Text('保存模板'),
          ),
          FilledButton.tonal(
            onPressed: _busy ? null : () => _generate(),
            child: const Text('本地生成预览'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        widget.agent?.hasModel == true
            ? 'AI 生成只发送此设计文档到 ${Uri.parse(widget.agent!.endpoint).host}，不发送片库。'
            : '使用自由描述生成，需要先在设置中接入 AI 模型。',
        style: WowType.body(11, color: WowColors.muted),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: !_busy && widget.agent?.hasModel == true
            ? () => _generate(ai: true)
            : null,
        icon: const Icon(Icons.auto_awesome_outlined, size: 16),
        label: const Text('使用 AI 生成预览'),
      ),
    ],
  );
  Widget _documentField(String label) => TextField(
    controller: _document,
    enabled: !_busy,
    minLines: 7,
    maxLines: 12,
    style: const TextStyle(fontFamily: WowType.mono, fontSize: 11),
    decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
  );
}
