import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/cinema_widgets.dart';
import '../design/tokens.dart';
import '../watch_ai/watch_ai_controller.dart';
import '../watch_ai/watch_ai_settings.dart';

import 'dart:typed_data';

Future<void> configureWatchAi(
  BuildContext context, {
  WatchAiSettings? settings,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _WatchAiConfigDialog(settings: settings ?? WatchAiSettings.I),
);

class WatchAiSettingsTile extends StatelessWidget {
  const WatchAiSettingsTile({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: WatchAiSettings.I,
    builder: (context, _) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.subtitles_outlined, color: WowColors.accent),
      title: const Text('AI 字幕与小映陪看', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        WatchAiSettings.I.config.enabled
            ? '已开启 · ${WatchAiSettings.I.config.host}'
            : '默认关闭 · 自行配置 API，按需开启',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => configureWatchAi(context),
    ),
  );
}

class _WatchAiConfigDialog extends StatefulWidget {
  const _WatchAiConfigDialog({required this.settings});
  final WatchAiSettings settings;
  @override
  State<_WatchAiConfigDialog> createState() => _WatchAiConfigDialogState();
}

class _WatchAiConfigDialogState extends State<_WatchAiConfigDialog> {
  late final _url = TextEditingController(
    text: widget.settings.config.endpoint,
  );
  late final _model = TextEditingController(text: widget.settings.config.model);
  final _key = TextEditingController();
  late bool _enabled = widget.settings.config.enabled;
  late bool _subtitles = widget.settings.config.subtitles;
  late bool _companion = widget.settings.config.companion;
  late bool _frames = widget.settings.config.allowFrames;
  late String _language = widget.settings.config.language;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.settings.configure(
        WatchAiConfig(
          enabled: _enabled,
          subtitles: _subtitles,
          companion: _companion,
          allowFrames: _frames,
          endpoint: _url.text.trim(),
          model: _model.text.trim(),
          language: _language,
        ),
        apiKey: _key.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException ? e.message : '无法保存配置，请检查系统凭据存储',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('AI 字幕与小映陪看'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '开启后，影片名、播放时间和当前台词会发送到你填写的 API。画面分析需单独开启，每次提问可选择附带一张截图。API 调用可能计费。',
                style: WowType.body(12, color: WowColors.muted),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '开启 AI 字幕与陪看',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  '默认关闭，可随时停止并清理会话',
                  style: TextStyle(fontSize: 11),
                ),
                value: _enabled,
                onChanged: _saving ? null : (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _url,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '完整 Chat Completions 接口',
                  hintText: 'https://你的服务/v1/chat/completions',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _model,
                enabled: !_saving,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: '画面分析需要支持图像输入的模型',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                enabled: !_saving,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '留空保留同一服务的密钥，本机服务可不填',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue:
                    ['简体中文', '繁體中文', 'English', '日本語'].contains(_language)
                    ? _language
                    : '简体中文',
                isExpanded: true,
                decoration: const InputDecoration(labelText: '翻译和解释语言'),
                items: [
                  for (final l in ['简体中文', '繁體中文', 'English', '日本語'])
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _language = v!),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动翻译已有字幕', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  '内嵌文字字幕 / 外挂 SRT、VTT；不包含语音识别',
                  style: TextStyle(fontSize: 11),
                ),
                value: _subtitles,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _subtitles = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('小映陪看', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  '主动提问后解释台词、文化背景和当前情节',
                  style: TextStyle(fontSize: 11),
                ),
                value: _companion,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _companion = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许按需分析画面', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  '截图会短时增加内存。最长边 640px，单张不超过 512 KB；不连续录屏',
                  style: TextStyle(fontSize: 11),
                ),
                value: _frames,
                onChanged: _saving ? null : (v) => setState(() => _frames = v),
              ),
              const SizedBox(height: 10),
              Text(
                '最多保留 16 段台词、48 条译文和 8 次问答。切换影片、退到后台或关闭功能时清理，不保存到片库。密钥存放于系统凭据存储。',
                style: WowType.body(11, color: WowColors.muted),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: WowColors.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存配置'),
        ),
      ],
    ),
  );
}

class WatchCompanionPanel extends StatefulWidget {
  const WatchCompanionPanel({
    super.key,
    required this.controller,
    required this.capture,
    required this.onImportSubtitle,
    required this.onSelectSubtitle,
  });
  final WatchAiController controller;
  final Future<Uint8List?> Function() capture;
  final Future<void> Function() onImportSubtitle, onSelectSubtitle;
  @override
  State<WatchCompanionPanel> createState() => _WatchCompanionPanelState();
}

class _WatchCompanionPanelState extends State<WatchCompanionPanel> {
  final _question = TextEditingController();
  bool _frame = false;
  WatchAiController get ai => widget.controller;
  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask(String q) async {
    if (!ai.active) return;
    final attachFrame = _frame && ai.config.allowFrames;
    setState(() => _frame = false);
    await ai.ask(q, withFrame: attachFrame, capture: widget.capture);
    if (mounted && ai.error == null) _question.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ai,
    builder: (context, _) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: WowColors.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.face_3_outlined,
                  color: WowColors.accent,
                  size: 29,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '小映陪看',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '把看不懂的地方，留给我。',
                      style: WowType.body(11, color: WowColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'AI 字幕与陪看设置',
                onPressed: () =>
                    configureWatchAi(context, settings: ai.settings),
                icon: const Icon(Icons.tune, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (!ai.config.enabled || !ai.config.configured)
                  CinemaPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '先接入你的 API',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '这是默认关闭的可选功能。开启后可以翻译已有字幕，或让我帮你理解台词和当前情节。',
                          style: WowType.body(12, color: WowColors.muted),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () =>
                              configureWatchAi(context, settings: ai.settings),
                          child: const Text('配置并选择开启'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    '当前信息来自 ${watchTime(ai.position)} 及之前的台词。默认不剧透，AI 解释可能有误。',
                    style: WowType.body(11, color: WowColors.muted),
                  ),
                  const SizedBox(height: 12),
                  if (ai.currentText.isEmpty)
                    Text(
                      '当前没有可读取的文字字幕。可选择字幕轨道或导入 SRT / VTT；解释场景也可按需附带画面。',
                      style: WowType.body(12, color: WowColors.muted),
                    )
                  else
                    CinemaPanel(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Eyebrow('当前台词'),
                          const SizedBox(height: 8),
                          SelectableText(
                            ai.currentText,
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (ai.translation != null) ...[
                            const SizedBox(height: 10),
                            SelectableText(
                              ai.translation!,
                              style: TextStyle(
                                fontSize: 13,
                                color: WowColors.accent,
                              ),
                            ),
                          ],
                          if (ai.translating)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.onSelectSubtitle,
                      icon: const Icon(Icons.subtitles_outlined, size: 16),
                      label: const Text('选择字幕'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onImportSubtitle,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('导入 SRT / VTT'),
                    ),
                  ],
                ),
                if (ai.active && ai.config.companion) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final q in [
                        '这句台词是什么意思？',
                        '解释一下当前情节',
                        '这里有什么文化背景？',
                        '这个场景有哪些值得注意的细节？',
                      ])
                        ActionChip(
                          label: Text(q, style: const TextStyle(fontSize: 11)),
                          onPressed: ai.busy ? null : () => _ask(q),
                        ),
                    ],
                  ),
                ],
                for (final answer in ai.answers)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: CinemaPanel(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${watchTime(answer.seconds)} · ${answer.usedFrame ? '台词与单帧画面' : '台词上下文'}',
                            style: WowType.body(10, color: WowColors.muted),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            answer.question,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            answer.answer,
                            style: WowType.body(13),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: '复制解释',
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: answer.answer),
                              ),
                              icon: const Icon(Icons.copy_outlined, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (ai.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      ai.error!,
                      style: TextStyle(color: WowColors.error, fontSize: 12),
                    ),
                  ),
                if (ai.busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
          if (ai.active && ai.config.companion) ...[
            if (ai.config.allowFrames)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('本次问题附带当前画面', style: TextStyle(fontSize: 12)),
                subtitle: const Text(
                  '仅一张截图，会发送到所配置的 API',
                  style: TextStyle(fontSize: 10),
                ),
                value: _frame,
                onChanged: ai.busy ? null : (v) => setState(() => _frame = v!),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _question,
              enabled: !ai.busy,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '例如：他为什么在这里说这句话？',
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: '向小映提问',
                  onPressed: ai.busy ? null : () => _ask(_question.text),
                  icon: const Icon(Icons.arrow_upward),
                ),
              ),
              onSubmitted: _ask,
            ),
          ],
          Row(
            children: [
              if (ai.busy || ai.translating)
                TextButton(onPressed: ai.stop, child: const Text('停止请求')),
              TextButton(onPressed: ai.clear, child: const Text('清理会话与缓存')),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('收起'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String watchTime(double seconds) {
  final n = seconds.floor();
  return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
}
