import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/media_item.dart';
import '../sources/native_bridge.dart';
import '../metadata/metadata_transport.dart';
import 'audio_capture.dart';

/// Two ways to reach a speech-to-speech service.
///
/// [seeWow] is the built-in segmented protocol (one JSON request per ~6 s
/// slice). [generic] renders a user-written JSON template and reads the audio
/// out of a dotted response path, so a vendor HTTP API can be wired without an
/// app update.
enum VoiceProtocol { seeWow, generic }

/// Placeholders accepted inside a generic body template. Values are inserted
/// JSON-escaped, so they must sit inside quotes (numbers may stand alone).
const voiceTemplateKeys = [
  'model',
  'target_language',
  'audio_base64',
  'audio_format',
  'source_at_ms',
  'source_duration_ms',
];

String _jsonInner(String value) {
  final encoded = jsonEncode(value);
  return encoded.substring(1, encoded.length - 1);
}

/// Replaces `{{key}}` with the escaped value and returns the rendered JSON
/// text. Numeric placeholders stay unquoted when the template leaves them bare.
String renderVoiceTemplate(
  String template, {
  required String model,
  required String language,
  required String audioBase64,
  required int atMs,
  required int durationMs,
}) {
  final values = <String, String>{
    'model': _jsonInner(model),
    'target_language': _jsonInner(language),
    'audio_base64': audioBase64,
    'audio_format': 'wav',
    'source_at_ms': '$atMs',
    'source_duration_ms': '$durationMs',
  };
  var out = template;
  values.forEach((key, value) {
    out = out.replaceAll('{{$key}}', value);
  });
  // Unknown placeholders are a configuration mistake, not an empty string.
  final leftover = RegExp(r'\{\{([a-zA-Z_]+)\}\}').firstMatch(out);
  if (leftover != null)
    throw FormatException('模板里有不支持的占位符 {{${leftover.group(1)}}}');
  return out;
}

/// Reads `data.audio_base64`, `choices.0.text` and similar dotted paths.
Object? voiceFieldAt(Object? json, String path) {
  if (path.trim().isEmpty) return null;
  Object? current = json;
  for (final segment in path.split('.')) {
    final key = segment.trim();
    if (key.isEmpty) return null;
    if (current is Map) {
      current = current[key];
    } else if (current is List) {
      final index = int.tryParse(key);
      current = index == null || index < 0 || index >= current.length
          ? null
          : current[index];
    } else {
      return null;
    }
  }
  return current;
}

final _pathPattern = RegExp(r'^[A-Za-z0-9_.]+$');

class VoiceTranslationConfig {
  const VoiceTranslationConfig({
    this.endpoint = '',
    this.model = '',
    this.language = 'zh-CN',
    this.allowLan = false,
    this.protocol = VoiceProtocol.seeWow,
    this.bodyTemplate = '',
    this.audioPath = 'data.audio_base64',
    this.textPath = '',
    this.voicePath = '',
    this.authHeader = 'Authorization',
    this.authBearer = true,
  });
  final String endpoint, model, language;
  final bool allowLan;
  final VoiceProtocol protocol;
  final String bodyTemplate, audioPath, textPath, voicePath;
  final String authHeader;
  final bool authBearer;
  void validate() {
    MetadataTransport.endpoint(endpoint);
    if (model.length > 160 ||
        !RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$').hasMatch(language))
      throw const FormatException('填写语音翻译模型与目标语言代码（如 zh-CN、ja-JP）');
    if (!RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(authHeader))
      throw const FormatException('认证头名称只能包含字母、数字与连字符');
    if (protocol == VoiceProtocol.seeWow) {
      if (model.trim().isEmpty)
        throw const FormatException('填写语音翻译模型与目标语言代码（如 zh-CN、ja-JP）');
      return;
    }
    final template = bodyTemplate.trim();
    if (template.isEmpty || template.length > 20000)
      throw const FormatException('请求模板为空或过长（上限 20 KB）');
    if (!template.contains('{{audio_base64}}'))
      throw const FormatException('通用适配的请求模板必须包含 {{audio_base64}}');
    if (!_pathPattern.hasMatch(audioPath) ||
        (textPath.isNotEmpty && !_pathPattern.hasMatch(textPath)) ||
        (voicePath.isNotEmpty && !_pathPattern.hasMatch(voicePath)))
      throw const FormatException('响应字段路径只能包含字母、数字、下划线与点');
    if (audioPath.isEmpty)
      throw const FormatException('请填写音频字段路径');
    // Prove the template is valid JSON once the placeholders are filled.
    final rendered = renderVoiceTemplate(
      template,
      model: model,
      language: language,
      audioBase64: 'AA==',
      atMs: 0,
      durationMs: 1000,
    );
    Object? decoded;
    try {
      decoded = jsonDecode(rendered);
    } catch (_) {
      throw const FormatException('请求模板不是合法 JSON；占位符要写在引号内');
    }
    if (decoded is! Map)
      throw const FormatException('请求模板必须是 JSON 对象');
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
      protocol: j['protocol'] == 'generic'
          ? VoiceProtocol.generic
          : VoiceProtocol.seeWow,
      bodyTemplate: j['bodyTemplate'] as String? ?? '',
      audioPath: j['audioPath'] as String? ?? 'data.audio_base64',
      textPath: j['textPath'] as String? ?? '',
      voicePath: j['voicePath'] as String? ?? '',
      authHeader: j['authHeader'] as String? ?? 'Authorization',
      authBearer: j['authBearer'] != false,
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
        'protocol': protocol.name,
        'bodyTemplate': bodyTemplate,
        'audioPath': audioPath,
        'textPath': textPath,
        'voicePath': voicePath,
        'authHeader': authHeader,
        'authBearer': authBearer,
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
    final atMs = (at * 1000).round();
    final durationMs = (audio.duration * 1000).round();
    final audioBase64 = base64Encode(audio.bytes);
    final headers = token.isEmpty
        ? const <String, String>{}
        : {config.authHeader: config.authBearer ? 'Bearer $token' : token};
    if (config.protocol == VoiceProtocol.generic) {
      final rendered = renderVoiceTemplate(
        config.bodyTemplate.trim(),
        model: config.model,
        language: config.language,
        audioBase64: audioBase64,
        atMs: atMs,
        durationMs: durationMs,
      );
      if (rendered.length > 6 * 1024 * 1024)
        throw const FormatException('渲染后的请求体超过 6 MiB，请检查模板重复引用了音频');
      Object? decoded;
      try {
        decoded = jsonDecode(rendered);
      } catch (_) {
        throw const FormatException('请求模板渲染后不是合法 JSON');
      }
      final mapped = await _http.json(
        Uri.parse(config.endpoint),
        allowLan: config.allowLan,
        maxBytes: 4 * 1024 * 1024,
        headers: headers,
        body: decoded is Map<String, dynamic>
            ? decoded
            : (decoded as Map).cast<String, dynamic>(),
      );
      return _readGeneric(mapped, audio);
    }
    final result = await _http.json(
      Uri.parse(config.endpoint),
      allowLan: config.allowLan,
      maxBytes: 4 * 1024 * 1024,
      headers: headers,
      body: {
        'model': config.model,
        'target_language': config.language,
        'preserve_voice': true,
        'source_at_ms': atMs,
        'source_duration_ms': durationMs,
        'source_audio': {'format': 'wav', 'base64': audioBase64},
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

  /// Reads a user-mapped response: audio is mandatory, text and the
  /// voice-preservation flag are optional.
  TranslatedSpeech _readGeneric(Object? result, WavAudio audio) {
    if (result is! Map) throw const FormatException('适配服务未返回 JSON 对象');
    final encoded = voiceFieldAt(result, config.audioPath);
    if (encoded is! String || encoded.isEmpty || encoded.length > 2800000)
      throw const FormatException('适配服务未返回有界的 Base64 WAV 译音');
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
    var text = '';
    if (config.textPath.isNotEmpty) {
      final node = voiceFieldAt(result, config.textPath);
      if (node != null && node is! String)
        throw const FormatException('译音文字字段不是字符串');
      text = node as String? ?? '';
      if (text.length > 4000)
        throw const FormatException('译音文字长度或格式无效');
    }
    if (config.voicePath.isNotEmpty &&
        voiceFieldAt(result, config.voicePath) != true)
      throw const FormatException('服务未声明音色保留，未替换原声');
    return TranslatedSpeech(translated, text);
  }

  void close() => _http.close();
}
