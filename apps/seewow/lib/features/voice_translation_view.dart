import 'package:flutter/material.dart';

import '../playback/voice_translation.dart';

Future<void> configureVoiceTranslation(BuildContext context) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VoiceTranslationSettings(),
    );

const _sampleTemplate = '''{
  "model": "{{model}}",
  "target_language": "{{target_language}}",
  "audio": "{{audio_base64}}",
  "at_ms": {{source_at_ms}},
  "duration_ms": {{source_duration_ms}}
}''';

class VoiceTranslationSettings extends StatefulWidget {
  const VoiceTranslationSettings({super.key});
  @override
  State<VoiceTranslationSettings> createState() =>
      _VoiceTranslationSettingsState();
}

class _VoiceTranslationSettingsState extends State<VoiceTranslationSettings> {
  final _endpoint = TextEditingController(),
      _model = TextEditingController(),
      _language = TextEditingController(text: 'zh-CN'),
      _token = TextEditingController(),
      _template = TextEditingController(),
      _audioPath = TextEditingController(text: 'data.audio_base64'),
      _textPath = TextEditingController(),
      _voicePath = TextEditingController(),
      _authHeader = TextEditingController(text: 'Authorization');
  bool _busy = true, _lan = false, _clear = false, _authBearer = true;
  VoiceProtocol _protocol = VoiceProtocol.seeWow;
  String? _error;
  @override
  void initState() {
    super.initState();
    VoiceTranslationConfig.load()
        .then((c) {
          if (mounted)
            setState(() {
              _endpoint.text = c.endpoint;
              _model.text = c.model;
              _language.text = c.language;
              _lan = c.allowLan;
              _protocol = c.protocol;
              _template.text = c.bodyTemplate;
              _audioPath.text = c.audioPath;
              _textPath.text = c.textPath;
              _voicePath.text = c.voicePath;
              _authHeader.text = c.authHeader;
              _authBearer = c.authBearer;
              _busy = false;
            });
        })
        .catchError((Object _) {
          if (mounted)
            setState(() {
              _busy = false;
              _error = '配置读取失败，请重新填写';
            });
        });
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _language.dispose();
    _token.dispose();
    _template.dispose();
    _audioPath.dispose();
    _textPath.dispose();
    _voicePath.dispose();
    _authHeader.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await VoiceTranslationConfig(
        endpoint: _endpoint.text.trim(),
        model: _model.text.trim(),
        language: _language.text.trim(),
        allowLan: _lan,
        protocol: _protocol,
        // Kept even in SeeWow mode: switching back and forth must not lose the
        // mapping someone already wrote.
        bodyTemplate: _template.text.trim(),
        audioPath: _audioPath.text.trim(),
        textPath: _textPath.text.trim(),
        voicePath: _voicePath.text.trim(),
        authHeader: _authHeader.text.trim(),
        authBearer: _authBearer,
      ).save(token: _token.text.trim(), clearToken: _clear);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException ? '${e.message}' : '译配服务保存失败',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('语音译配 API · 实验性'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '连接能把原音频翻译成目标语言并保留说话人音色的服务。两种接法：SeeWow 分段协议，或把你手上服务的 HTTP JSON 接口映射进来（自写请求模板 + 响应字段路径）。',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VoiceProtocol>(
                initialValue: _protocol,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '接入方式'),
                items: const [
                  DropdownMenuItem(
                    value: VoiceProtocol.seeWow,
                    child: Text('SeeWow 分段语音适配协议（内置）'),
                  ),
                  DropdownMenuItem(
                    value: VoiceProtocol.generic,
                    child: Text('通用 JSON 适配（自写模板与字段映射）'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(
                        () => _protocol = v ?? VoiceProtocol.seeWow,
                      ),
              ),
              TextField(
                controller: _endpoint,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '完整语音适配接口地址'),
              ),
              TextField(
                controller: _model,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: '语音翻译模型',
                  helperText: _protocol == VoiceProtocol.generic
                      ? '可留空；模板里仍可用 {{model}} 占位'
                      : null,
                ),
              ),
              TextField(
                controller: _language,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '目标语言代码',
                  hintText: 'zh-CN / ja-JP / ko-KR / ar-SA / bo-CN …',
                ),
              ),
              TextField(
                controller: _token,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API 密钥（可选）',
                  helperText: '留空保留同地址密钥；换地址需重新填写。通用适配固定以 Bearer 发送',
                  helperMaxLines: 2,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _authHeader,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: '认证头名称',
                        hintText: 'Authorization',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _authBearer,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _authBearer = v ?? true),
                      title: const Text(
                        '以 Bearer 前缀发送',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              if (_protocol == VoiceProtocol.generic) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _template,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 10,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    labelText: '请求 JSON 模板',
                    hintText: _sampleTemplate,
                    helperText:
                        '占位符：${voiceTemplateKeys.map((k) => '{{$k}}').join(' ')}；文本值要写在引号内',
                    helperMaxLines: 3,
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _template.text = _sampleTemplate),
                  child: const Text('填入示例模板'),
                ),
                TextField(
                  controller: _audioPath,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '响应音频字段路径',
                    hintText: 'data.audio_base64',
                    helperText: 'Base64 WAV；只接受 PCM 16-bit，单段 ≤2 MiB',
                  ),
                ),
                TextField(
                  controller: _textPath,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '响应文字字段路径（可选）',
                    hintText: 'data.text',
                  ),
                ),
                TextField(
                  controller: _voicePath,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '音色保留字段路径（可选）',
                    hintText: 'data.voice_preserved',
                    helperText: '填了就要求该字段为 true，否则不替换原声；留空表示信任服务',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '通用适配只发送你模板里写明的字段。目标语言不会自动写进请求，需要时请在模板里用 {{target_language}}。',
                ),
              ],
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
                title: const Text('清除当前地址的密钥'),
              ),
              const Text(
                '每段最多约 6 秒，保留原文件，以 1× 速度进行缓冲译配；准备不及时会暂停等候。音色由服务声明保留，无法保证完全一致。直播、受 AI 限制的来源及后台不发送音频；跳播、切片和停止会取消。',
              ),
              const SizedBox(height: 8),
              Text(
                _protocol == VoiceProtocol.seeWow
                    ? '协议：POST model、target_language、preserve_voice:true、source_at_ms、source_duration_ms、source_audio:{format:"wav",base64:"…"}；响应 audio_base64（PCM WAV）、target_language、voice_preserved:true 和可选 text。单段最长等待 45 秒，拒绝返回音频链接。'
                    : '通用适配：请求体由模板渲染，响应用点路径取字段。单段最长等待 45 秒；音频必须是 Base64 PCM WAV，时长与原片段相差超过 15% 会拒绝替换。',
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
          child: const Text('保存语音服务'),
        ),
      ],
    ),
  );
}
