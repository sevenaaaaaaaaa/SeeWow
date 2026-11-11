import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'watch_ai_settings.dart';

class WatchAiCancelled implements Exception {}

/// One bounded request at a time; redirects never receive the API credential.
class WatchAiClient {
  WatchAiClient(this.settings);
  final WatchAiSettings settings;
  HttpClient? _active;
  int _revision = 0;
  void cancel() {
    _revision++;
    _active?.close(force: true);
    _active = null;
  }

  Future<String> complete({
    required WatchAiConfig config,
    required String system,
    required String prompt,
    Uint8List? frame,
  }) async {
    if (!config.enabled || !config.configured) throw StateError('AI 陪看尚未开启或配置');
    config.validate();
    if (frame != null && (!config.allowFrames || frame.length > 512 * 1024)) {
      throw const FormatException('画面分析未开启，或图片超过 512 KB');
    }
    cancel();
    final ticket = _revision;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _active = client;
    try {
      // Deadline includes keychain, connection, response and all body chunks.
      return await (() async {
        final key =
            await settings.readSecret(
              WatchAiSettings.secretKey(config.endpoint),
            ) ??
            '';
        if (ticket != _revision) throw WatchAiCancelled();
        final req = await client.postUrl(Uri.parse(config.endpoint));
        req.followRedirects = false;
        req.headers.contentType = ContentType.json;
        if (key.isNotEmpty) req.headers.set('Authorization', 'Bearer $key');
        req.write(
          jsonEncode({
            'model': config.model,
            'stream': false,
            'max_tokens': 700,
            'messages': [
              {'role': 'system', 'content': system},
              {
                'role': 'user',
                'content': frame == null
                    ? prompt
                    : [
                        {'type': 'text', 'text': prompt},
                        {
                          'type': 'image_url',
                          'image_url': {
                            'url':
                                'data:image/png;base64,${base64Encode(frame)}',
                            'detail': 'low',
                          },
                        },
                      ],
              },
            ],
          }),
        );
        final response = await req.close();
        if (response.statusCode != 200)
          throw HttpException(
            'API 返回 HTTP ${response.statusCode}，请检查模型、密钥或视觉能力',
          );
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 128 * 1024)
            throw const FormatException('AI 响应超过 128 KB');
        }
        if (ticket != _revision) throw WatchAiCancelled();
        final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final answer = raw['choices']?[0]?['message']?['content'];
        if (answer is! String || answer.trim().isEmpty)
          throw const FormatException('模型没有返回有效文本');
        if (answer.length > 4000)
          throw const FormatException('模型回答过长，请使用简洁输出模型');
        return answer.trim();
      })().timeout(const Duration(seconds: 35));
    } catch (e) {
      if (ticket != _revision) throw WatchAiCancelled();
      rethrow;
    } finally {
      client.close(force: true);
      if (identical(_active, client)) _active = null;
    }
  }
}
