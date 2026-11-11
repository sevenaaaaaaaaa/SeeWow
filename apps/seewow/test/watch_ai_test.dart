import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/watch_ai/watch_ai_client.dart';
import 'package:seewow/watch_ai/watch_ai_controller.dart';
import 'package:seewow/watch_ai/watch_ai_settings.dart';

class _FakeClient extends WatchAiClient {
  _FakeClient(super.settings);
  final List<Map<String, dynamic>> requests = [];
  Completer<String>? pending;
  Object? failure;
  @override
  Future<String> complete({
    required WatchAiConfig config,
    required String system,
    required String prompt,
    Uint8List? frame,
  }) async {
    requests.add({'system': system, 'prompt': prompt, 'frame': frame});
    if (failure != null) throw failure!;
    return pending?.future ?? '这是一句翻译或当前场景的解释。';
  }
}

const _enabled = WatchAiConfig(
  enabled: true,
  endpoint: 'https://api.example.test/v1/chat/completions',
  model: 'movie-model',
);
void main() {
  late Directory dir;
  late WatchAiSettings settings;
  late _FakeClient client;
  late WatchAiController ai;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-watch-ai-');
    settings = WatchAiSettings(
      directory: dir,
      readSecret: (_) async => null,
      writeSecret: (_, _) async {},
    );
    client = _FakeClient(settings);
    ai = WatchAiController(
      title: 'Test Movie',
      settings: settings,
      client: client,
      translationDelay: const Duration(hours: 1),
      minimumInterval: Duration.zero,
    );
  });
  tearDown(() async {
    ai.dispose();
    settings.dispose();
    await dir.delete(recursive: true);
  });

  test('default off produces no API traffic, history or captures', () async {
    var captures = 0;
    ai.setSubtitle('Hello');
    await ai.translateCurrent();
    await ai.ask(
      'Explain',
      capture: () async {
        captures++;
        return Uint8List(1);
      },
      withFrame: true,
    );
    expect(client.requests, isEmpty);
    expect(ai.cues, isEmpty);
    expect(captures, 0);
  });
  test(
    'secrets are scoped to API origin and never persisted in preferences',
    () async {
      final secrets = <String, String>{};
      final custom = WatchAiSettings(
        directory: dir,
        readSecret: (k) async => secrets[k],
        writeSecret: (k, v) async => secrets[k] = v,
      );
      await custom.configure(_enabled, apiKey: 'my-private-key');
      final contents = await File('${dir.path}/watch-ai.json').readAsString();
      expect(contents.contains('my-private-key'), false);
      expect(secrets.keys.single, WatchAiSettings.secretKey(_enabled.endpoint));
      expect(
        WatchAiSettings.secretKey('https://another.test/v1/chat/completions'),
        isNot(secrets.keys.single),
      );
      final restored = WatchAiSettings(directory: dir);
      await restored.load();
      expect(restored.config.enabled, true);
      custom.dispose();
      restored.dispose();
    },
  );
  test('cue translations are cached and never shown against a different current line', () async {
    await settings.configure(_enabled);
    ai.setSubtitle('Hello');
    await ai.translateCurrent();
    expect(ai.translation, isNotNull);
    ai.setSubtitle('Different line');
    expect(ai.translation, isNull);
    ai.setSubtitle('Hello');
    await ai.translateCurrent();
    expect(client.requests.length, 1);
  });
  test('pending translation cannot overwrite a newer subtitle', () async {
    await settings.configure(_enabled);
    client.pending = Completer<String>();
    ai.setSubtitle('Before');
    final request = ai.translateCurrent();
    ai.setSubtitle('After');
    client.pending!.complete('旧译文');
    await request;
    expect(ai.translation, isNull);
    expect(ai.currentText, 'After');
  });
  test('bounded subtitles, translations and answers keep memory independent of film length', () async {
    await settings.configure(_enabled);
    for (var n = 0; n < 80; n++) {
      ai.setPosition(n.toDouble());
      ai.setSubtitle('Line $n');
      await ai.translateCurrent();
    }
    expect(ai.cues.length, 16);
    expect(ai.cacheCount, 48);
    for (var n = 0; n < 12; n++) {
      await ai.ask('Question $n');
    }
    expect(ai.answers.length, 8);
    final prompt = jsonDecode(client.requests.last['prompt'] as String) as Map;
    expect((prompt['recentSubtitles'] as List).length, lessThanOrEqualTo(16));
    expect(prompt.containsKey('locator'), false);
    expect(prompt.containsKey('overview'), false);
    expect(client.requests.last['frame'], isNull);
  });
  test(
    'seek drops future context and cancellation ignores late answers',
    () async {
      await settings.configure(_enabled);
      ai.setPosition(100);
      ai.setSubtitle('Later scene');
      ai.setPosition(10);
      ai.setSubtitle('Earlier scene');
      await ai.ask('What happened?');
      expect(
        (client.requests.last['prompt'] as String).contains('Later scene'),
        false,
      );
      client.pending = Completer<String>();
      final future = ai.ask('Pending');
      ai.stop();
      client.pending!.complete('obsolete');
      await future;
      expect(ai.answers.length, 1);
    },
  );
  test('frames require explicit opt in and a per-question capture', () async {
    await settings.configure(_enabled);
    var captures = 0;
    await ai.ask(
      'Scene',
      withFrame: true,
      capture: () async {
        captures++;
        return Uint8List(1);
      },
    );
    expect(captures, 0);
    expect(client.requests, isEmpty);
    await settings.configure(
      const WatchAiConfig(
        enabled: true,
        allowFrames: true,
        endpoint: 'https://example.test/chat',
        model: 'vision',
      ),
    );
    await ai.ask(
      'Scene',
      withFrame: true,
      capture: () async {
        captures++;
        return Uint8List(1);
      },
    );
    expect(captures, 1);
    expect(ai.answers.single.usedFrame, true);
    expect(ai.answers.single.answer.contains('base64'), false);
  });
  test('turning off or going to background cancels work and clears retained context', () async {
    await settings.configure(_enabled);
    ai.setSubtitle('Hello');
    await ai.ask('Meaning?');
    ai.suspend(true);
    expect(ai.answers, isEmpty);
    expect(ai.cues, isEmpty);
    expect(ai.cacheCount, 0);
    final count = client.requests.length;
    await ai.ask('Background');
    await ai.translateCurrent();
    expect(client.requests.length, count);
    ai.suspend(false);
    await settings.configure(const WatchAiConfig());
    await ai.ask('Disabled');
    expect(client.requests.length, count);
  });
  test('API errors never create successful companion responses', () async {
    await settings.configure(_enabled);
    client.failure = const HttpException('failed');
    ai.setSubtitle('Hello');
    await ai.ask('Meaning?');
    expect(ai.answers, isEmpty);
    expect(ai.error, isNotNull);
    expect(ai.busy, false);
  });
  test('returning to foreground publishes state and restores companion availability', () async {
    await settings.configure(_enabled);
    ai.suspend(true);
    var changes = 0;
    ai.addListener(() => changes++);
    ai.suspend(false);
    expect(ai.active, true);
    expect(changes, greaterThan(0));
  });
  test(
    'revoking frame consent while capture is pending prevents transmission',
    () async {
      await settings.configure(
        const WatchAiConfig(
          enabled: true,
          allowFrames: true,
          endpoint: 'https://example.test/chat',
          model: 'vision',
        ),
      );
      final capture = Completer<Uint8List?>();
      final pending = ai.ask(
        'Describe',
        withFrame: true,
        capture: () => capture.future,
      );
      await settings.configure(_enabled);
      capture.complete(Uint8List(4));
      await pending;
      expect(client.requests, isEmpty);
      expect(ai.answers, isEmpty);
    },
  );
  test('real HTTP request contains only bounded viewing context and rejects redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var redirected = false;
    server.listen((req) async {
      if (req.uri.path == '/redirect') {
        req.response.statusCode = 302;
        req.response.headers.set('Location', '/target');
      } else if (req.uri.path == '/target') {
        redirected = true;
      } else {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        expect(body['stream'], false);
        expect(body['messages'][1]['content'], '{"line":"Hello"}');
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '你好'},
              },
            ],
          }),
        );
      }
      await req.response.close();
    });
    final real = WatchAiClient(settings);
    try {
      final response = await real.complete(
        config: WatchAiConfig(
          enabled: true,
          endpoint: 'http://127.0.0.1:${server.port}/chat',
          model: 'model',
        ),
        system: 'Translate',
        prompt: '{"line":"Hello"}',
      );
      expect(response, '你好');
      await expectLater(
        real.complete(
          config: WatchAiConfig(
            enabled: true,
            endpoint: 'http://127.0.0.1:${server.port}/redirect',
            model: 'model',
          ),
          system: 'Translate',
          prompt: 'Hello',
        ),
        throwsA(isA<HttpException>()),
      );
      expect(redirected, false);
    } finally {
      real.cancel();
      await server.close(force: true);
    }
  });
}
