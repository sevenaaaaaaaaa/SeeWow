import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/media_item.dart';
import '../sources/native_bridge.dart';
import '../metadata/metadata_transport.dart';
import 'audio_capture.dart';

class VoiceTranslationConfig {
  const VoiceTranslationConfig({
    this.endpoint = '',
    this.model = '',
    this.language = 'zh-CN',
    this.allowLan = false,
  });
  final String endpoint, model, language;
  final bool allowLan;
  void validate() {
    MetadataTransport.endpoint(endpoint);
    if (model.trim().isEmpty ||
        model.length > 160 ||
        !RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$').hasMatch(language))
      throw const FormatException('填写语音翻译模型与目标语言代码（如 zh-CN、ja-JP）');
  }

  static const key = 'playback.voiceTranslation';
  String get secretKey =>
      'playback.voice.key.${sha256.convert(utf8.encode(endpoint))}';
  static Future<VoiceTranslationConfig> load() async {
    final raw = await NativeBridge.secretRead(key);
    if (raw == null) return const VoiceTranslationConfig();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return VoiceTranslationConfig(
      endpoint: j['endpoint'] as String? ?? '',
      model: j['model'] as String? ?? '',
      language: j['language'] as String? ?? 'zh-CN',
      allowLan: j['allowLan'] == true,
    );
  }

  Future<void> save({String token = '', bool clearToken = false}) async {
    validate();
    if (token.length > 4096 || token.contains(RegExp(r'[\r\n]')))
      throw const FormatException('密钥格式无效');
    if (clearToken) await NativeBridge.secretDelete(secretKey);
    if (token.isNotEmpty) await NativeBridge.secretWrite(secretKey, token);
    await NativeBridge.secretWrite(
      key,
      jsonEncode({
        'endpoint': endpoint,
        'model': model,
        'language': language,
        'allowLan': allowLan,
      }),
    );
  }
}

class TranslatedSpeech {
  const TranslatedSpeech(this.audio, this.text);
  final WavAudio audio;
  final String text;
}

/// SeeWow speech-to-speech adapter contract; not a generic text completion API.
class VoiceTranslationClient {
  VoiceTranslationClient(
    this.config, {
    this.token = '',
    MetadataTransport? transport,
  }) : _http =
           transport ?? MetadataTransport(timeout: const Duration(seconds: 45));
  final VoiceTranslationConfig config;
  final String token;
  final MetadataTransport _http;
  Future<TranslatedSpeech> translate(
    MediaItem item,
    WavAudio audio,
    double at,
  ) async {
    if (!item.aiAllowed) throw const FormatException('此来源不允许 AI 处理');
    config.validate();
    if (!at.isFinite || at < 0 || audio.duration > 8.5)
      throw const FormatException('语音片段范围无效');
    final result = await _http.json(
      Uri.parse(config.endpoint),
      allowLan: config.allowLan,
      maxBytes: 4 * 1024 * 1024,
      headers: token.isEmpty ? {} : {'Authorization': 'Bearer $token'},
      body: {
        'model': config.model,
        'target_language': config.language,
        'preserve_voice': true,
        'source_at_ms': (at * 1000).round(),
        'source_duration_ms': (audio.duration * 1000).round(),
        'source_audio': {'format': 'wav', 'base64': base64Encode(audio.bytes)},
      },
    );
    if (result is! Map ||
        result['target_language'] != config.language ||
        result['voice_preserved'] != true)
      throw const FormatException('服务未确认目标语言或音色保留能力，未替换原声');
    final encoded = result['audio_base64'];
    if (encoded is! String || encoded.length > 2800000)
      throw const FormatException('服务未返回有界的 Base64 WAV 译音');
    Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      throw const FormatException('译音 Base64 无效');
    }
    final translated = WavAudio.parse(bytes);
    if ((translated.duration - audio.duration).abs() >
        audio.duration * .15 + .05)
      throw const FormatException('译音与原片段时长差异过大，无法同步；请让服务返回对齐音频');
    final text = result['text'] ?? '';
    if (text is! String || text.length > 4000)
      throw const FormatException('译音文字长度或格式无效');
    return TranslatedSpeech(translated, text);
  }

  void close() => _http.close();
}
