import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import '../domain/media_item.dart';
import '../sources/native_bridge.dart';
import 'metadata_transport.dart';

class CoverGenerationConfig {
  const CoverGenerationConfig({
    this.endpoint = '',
    this.model = '',
    this.size = '1024x1536',
    this.requestBase64 = false,
    this.allowLan = false,
  });
  final String endpoint, model, size;
  final bool requestBase64, allowLan;
  void validate() {
    MetadataTransport.endpoint(endpoint);
    if (!Uri.parse(endpoint).path.endsWith('/images/generations') ||
        model.trim().isEmpty ||
        model.length > 160)
      throw const FormatException('填写完整的 /images/generations 地址与图像模型名称');
    if (!['1024x1536', '1024x1024', '1024x1792', 'auto'].contains(size))
      throw const FormatException('图片尺寸无效');
  }

  String get credentialKey =>
      'metadata.cover.key.${sha256.convert(utf8.encode(endpoint))}';
  static const key = 'metadata.cover.config';
  Map<String, dynamic> toJson() => {
    'endpoint': endpoint,
    'model': model,
    'size': size,
    'requestBase64': requestBase64,
    'allowLan': allowLan,
  };
  static Future<CoverGenerationConfig> load() async {
    final raw = await NativeBridge.secretRead(key);
    if (raw == null) return const CoverGenerationConfig();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return CoverGenerationConfig(
      endpoint: j['endpoint'] as String? ?? '',
      model: j['model'] as String? ?? '',
      size: j['size'] as String? ?? '1024x1536',
      requestBase64: j['requestBase64'] == true,
      allowLan: j['allowLan'] == true,
    );
  }

  Future<void> save({String token = '', bool clearToken = false}) async {
    validate();
    if (token.length > 4096 || token.contains(RegExp(r'[\r\n]')))
      throw const FormatException('密钥格式无效');
    if (clearToken) await NativeBridge.secretDelete(credentialKey);
    if (token.isNotEmpty) await NativeBridge.secretWrite(credentialKey, token);
    await NativeBridge.secretWrite(key, jsonEncode(toJson()));
  }
}

class GeneratedCover {
  const GeneratedCover({
    required this.bytes,
    required this.model,
    required this.createdAt,
  });
  final Uint8List bytes;
  final String model;
  final DateTime createdAt;
}

class CoverGenerator {
  CoverGenerator(this.config, {this.token = '', MetadataTransport? transport})
    : _http =
          transport ?? MetadataTransport(timeout: const Duration(seconds: 180));
  final CoverGenerationConfig config;
  final String token;
  final MetadataTransport _http;

  static String initialPrompt(MediaItem item) =>
      'Create an original vertical cover illustration for a personal media library. '
      'Title: ${item.title}. Category: ${item.genres.join(', ')}. '
      'Synopsis: ${item.overview.length > 1200 ? item.overview.substring(0, 1200) : item.overview}. '
      'Use an evocative composition with no text, logos, ratings or official-poster claims. '
      'Do not imitate an existing poster or depict identifiable real people. No explicit imagery.';

  Future<GeneratedCover> generate(MediaItem item, String prompt) async {
    if (!item.aiAllowed) throw const FormatException('此来源不允许 AI 处理');
    config.validate();
    if (prompt.trim().isEmpty || prompt.length > 6000)
      throw const FormatException('封面描述需为 1–6000 字');
    final response = await _http.json(
      Uri.parse(config.endpoint),
      headers: token.isEmpty ? {} : {'Authorization': 'Bearer $token'},
      allowLan: config.allowLan,
      maxBytes: 28 * 1024 * 1024,
      body: {
        'model': config.model,
        'prompt': prompt.trim(),
        'n': 1,
        'size': config.size,
        if (config.requestBase64) 'response_format': 'b64_json',
      },
    );
    final data = response is Map ? response['data'] : null;
    final encoded = data is List && data.isNotEmpty && data.first is Map
        ? data.first['b64_json']
        : null;
    if (encoded is! String || encoded.isEmpty)
      throw const FormatException(
        '接口需返回 data[0].b64_json 图片；仅返回 URL 的服务请启用 Base64 选项或使用兼容适配器',
      );
    if (encoded.length > 28 * 1024 * 1024)
      throw const FormatException('图片超过大小限制');
    Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      throw const FormatException('图片 Base64 无效');
    }
    await validateCoverBytes(bytes);
    return GeneratedCover(
      bytes: bytes,
      model: config.model,
      createdAt: DateTime.now().toUtc(),
    );
  }

  void close() => _http.close();
}

/// Validate the encoded raster and dimensions before allocating a decoded image.
Future<void> validateCoverBytes(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024)
    throw const FormatException('图片为空或超过 20 MiB');
  final png =
      bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71;
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
  final webp =
      bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
  if (!png && !jpeg && !webp)
    throw const FormatException('仅接受 PNG、JPEG 或 WebP 栅格封面');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width < 1 ||
        descriptor.height < 1 ||
        descriptor.width > 8192 ||
        descriptor.height > 8192 ||
        descriptor.width * descriptor.height > 20 * 1000 * 1000)
      throw const FormatException('图片尺寸超过限制');
    codec = await descriptor.instantiateCodec(
      targetWidth: descriptor.width > 256 ? 256 : descriptor.width,
    );
    image = (await codec.getNextFrame()).image;
  } catch (_) {
    throw const FormatException('图片损坏或尺寸超过限制');
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
