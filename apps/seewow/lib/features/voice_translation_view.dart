import 'package:flutter/material.dart';

import '../playback/voice_translation.dart';

Future<void> configureVoiceTranslation(BuildContext context) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VoiceTranslationSettings(),
    );

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
      _token = TextEditingController();
  bool _busy = true, _lan = false, _clear = false;
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
                '连接能把原音频翻译成目标语言并保留说话人音色的服务。采用 SeeWow 分段语音适配协议，不是普通文字翻译或单一 TTS 接口；第三方服务可能需要你自己的适配层。',
              ),
              TextField(
                controller: _endpoint,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '完整语音适配接口地址'),
              ),
              TextField(
                controller: _model,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '语音翻译模型'),
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
                  helperText: '留空保留同地址密钥；换地址需重新填写',
                  helperMaxLines: 2,
                ),
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
                title: const Text('清除当前地址的密钥'),
              ),
              const Text(
                '每段最多约 6 秒，保留原文件，以 1× 速度进行缓冲译配；准备不及时会暂停等候。音色由服务声明保留，无法保证完全一致。直播、受 AI 限制的来源及后台不发送音频；跳播、切片和停止会取消。',
              ),
              const SizedBox(height: 8),
              const Text(
                '协议：POST model、target_language、preserve_voice:true、source_at_ms、source_duration_ms、source_audio:{format:"wav",base64:"…"}；响应 audio_base64（PCM WAV）、target_language、voice_preserved:true 和可选 text。单段最长等待 45 秒，拒绝返回音频链接。',
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
