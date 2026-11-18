import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/playback/audio_capture.dart';
import 'package:seewow/playback/voice_translation.dart';

Uint8List _wav({int samples = 16000}) {
  final dataLength = samples * 2;
  final bytes = Uint8List(44 + dataLength);
  final view = ByteData.sublistView(bytes);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes[offset + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, 16000, Endian.little);
  view.setUint32(28, 32000, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataLength, Endian.little);
  return bytes;
}

MediaItem _item() => MediaItem(
  id: 'm1',
  sourceId: 'nas',
  kind: MediaKind.movie,
  title: 'Demo',
  locator: '/media/demo.mkv',
);

void main() {
  group('request template', () {
    test('values are JSON-escaped, numbers stay numbers', () {
      final rendered = renderVoiceTemplate(
        '{"model":"{{model}}","lang":"{{target_language}}","audio":"{{audio_base64}}","at":{{source_at_ms}},"ms":{{source_duration_ms}}}',
        model: 'a"b\\c\n',
        language: 'zh-CN',
        audioBase64: 'AA==',
        atMs: 1234,
        durationMs: 5000,
      );
      final decoded = jsonDecode(rendered) as Map<String, dynamic>;
      expect(decoded['model'], 'a"b\\c\n');
      expect(decoded['lang'], 'zh-CN');
      expect(decoded['audio'], 'AA==');
      expect(decoded['at'], 1234);
      expect(decoded['ms'], 5000);
    });

    test('an unknown placeholder is a configuration error', () {
      expect(
        () => renderVoiceTemplate(
          '{"audio":"{{audio_base64}}","x":"{{secret}}"}',
          model: '',
          language: 'zh-CN',
          audioBase64: 'AA==',
          atMs: 0,
          durationMs: 1,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('{{secret}}'),
          ),
        ),
      );
    });
  });

  group('generic config validation', () {
    VoiceTranslationConfig generic({
      String template = '{"audio":"{{audio_base64}}","model":"{{model}}"}',
      String audioPath = 'data.audio',
    }) => VoiceTranslationConfig(
      endpoint: 'https://example.test/translate',
      model: 'voice-1',
      language: 'zh-CN',
      protocol: VoiceProtocol.generic,
      bodyTemplate: template,
      audioPath: audioPath,
    );

    test('requires audio_base64 in the template', () {
      expect(
        () => generic(template: '{"model":"{{model}}"}').validate(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('audio_base64'),
          ),
        ),
      );
    });

    test('rejects a template that is not JSON once rendered', () {
      expect(
        () => generic(template: '{"audio":"{{audio_base64}}" "model":"{{model}}"}').validate(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('合法 JSON'),
          ),
        ),
      );
    });

    test('accepts a well-formed mapping and keeps model optional', () {
      VoiceTranslationConfig(
        endpoint: 'https://example.test/translate',
        model: '',
        language: 'ja-JP',
        protocol: VoiceProtocol.generic,
        bodyTemplate: '{"audio":"{{audio_base64}}","target":"{{target_language}}"}',
        audioPath: 'data.audio_base64',
      ).validate();
    });

    test('rejects an invalid auth header name', () {
      expect(
        () => VoiceTranslationConfig(
          endpoint: 'https://example.test/translate',
          model: '',
          language: 'zh-CN',
          protocol: VoiceProtocol.generic,
          bodyTemplate: '{"audio":"{{audio_base64}}"}',
          audioPath: 'data.audio',
          authHeader: 'X Key',
        ).validate(),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects response paths with other characters', () {
      expect(
        () => generic(audioPath: 'data/audio').validate(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('generic transport', () {
    late HttpServer server;
    late String base;
    late Map<String, dynamic> received;
    late Map<String, dynamic> reply;
    late String? authorization;
    late String? customHeader;

    setUp(() async {
      received = {};
      authorization = null;
      customHeader = null;
      final wav = _wav();
      reply = {
        'data': {
          'audio_base64': base64Encode(wav),
          'text': '你好',
          'voice': true,
        },
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        authorization = request.headers.value('Authorization');
        customHeader = request.headers.value('api-key');
        received =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(reply));
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    VoiceTranslationConfig config({String voicePath = 'data.voice'}) =>
        VoiceTranslationConfig(
          endpoint: '$base/translate',
          model: 'voice-1',
          language: 'zh-CN',
          protocol: VoiceProtocol.generic,
          bodyTemplate:
              '{"model":"{{model}}","target_language":"{{target_language}}","audio":"{{audio_base64}}","at":{{source_at_ms}}}',
          audioPath: 'data.audio_base64',
          textPath: 'data.text',
          voicePath: voicePath,
        );

    test('renders the template, posts it and maps the response', () async {
      final client = VoiceTranslationClient(config(), token: 'secret');
      addTearDown(client.close);
      final speech = await client.translate(_item(), WavAudio.parse(_wav()), 2);
      expect(authorization, 'Bearer secret');
      expect(received['model'], 'voice-1');
      expect(received['target_language'], 'zh-CN');
      expect(received['at'], 2000);
      expect(base64Decode(received['audio'] as String), _wav());
      expect(speech.text, '你好');
      expect(speech.audio.duration, closeTo(1, 0.01));
    });

    test('a false voice flag stops the replacement', () async {
      reply = {
        'data': {'audio_base64': base64Encode(_wav()), 'voice': false},
      };
      final client = VoiceTranslationClient(config());
      addTearDown(client.close);
      await expectLater(
        client.translate(_item(), WavAudio.parse(_wav()), 0),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('音色'),
          ),
        ),
      );
    });

    test('a missing audio field is reported, not guessed', () async {
      reply = {
        'data': {'text': 'only text'},
      };
      final client = VoiceTranslationClient(config());
      addTearDown(client.close);
      await expectLater(
        client.translate(_item(), WavAudio.parse(_wav()), 0),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Base64 WAV'),
          ),
        ),
      );
    });

    test('a custom auth header sends the raw token', () async {
      final client = VoiceTranslationClient(
        VoiceTranslationConfig(
          endpoint: '$base/translate',
          model: 'voice-1',
          language: 'zh-CN',
          protocol: VoiceProtocol.generic,
          bodyTemplate: '{"audio":"{{audio_base64}}"}',
          audioPath: 'data.audio_base64',
          authHeader: 'api-key',
          authBearer: false,
        ),
        token: 'k-123',
      );
      addTearDown(client.close);
      await client.translate(_item(), WavAudio.parse(_wav()), 0);
      expect(customHeader, 'k-123');
      expect(authorization, isNull);
    });

    test('the built-in SeeWow protocol still round-trips', () async {
      reply = {
        'target_language': 'zh-CN',
        'voice_preserved': true,
        'audio_base64': base64Encode(_wav()),
        'text': '你好',
      };
      final client = VoiceTranslationClient(
        VoiceTranslationConfig(
          endpoint: '$base/translate',
          model: 'seeWow-1',
          language: 'zh-CN',
        ),
      );
      addTearDown(client.close);
      final speech = await client.translate(_item(), WavAudio.parse(_wav()), 1);
      expect(received['preserve_voice'], true);
      expect((received['source_audio'] as Map)['format'], 'wav');
      expect(speech.text, '你好');
    });
  });
}
