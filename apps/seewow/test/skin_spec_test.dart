import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/skin_generator.dart';
import 'package:seewow/design/skin_spec.dart';
import 'package:seewow/design/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('built-in and community examples are legible portable skins', () {
    for (final spec in [...builtInSkins, ...communityExamples]) {
      expect(SkinSpec.decode(spec.encode()).encode(), spec.encode());
      for (final surface in ['background', 'shell', 'panel']) {
        for (final text in ['text', 'muted']) {
          expect(
            SkinSpec.contrast(spec.color(text), spec.color(surface)),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(
        SkinSpec.contrast(spec.onAccent, spec.color('accent')),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
  test('light mode changes Material controls and semantic foregrounds', () {
    WowSkin.I.use(builtInSkins[1]);
    expect(buildWowTheme().brightness, Brightness.light);
    expect(
      buildWowTheme().colorScheme.onSurface,
      builtInSkins[1].color('text'),
    );
    expect(
      buildWowTheme().colorScheme.primary,
      builtInSkins[1].color('accent'),
    );
    WowSkin.I.reset();
  });
  test('bad contrast, unknown fields, invalid dimensions and unsupported versions fail closed', () {
    final raw = builtInSkins.first.toJson();
    expect(
      () => SkinSpec.fromJson({...raw, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => SkinSpec.fromJson({...raw, 'script': 'anything'}),
      throwsFormatException,
    );
    expect(
      () => SkinSpec.fromJson({...raw, 'blur': double.nan}),
      throwsFormatException,
    );
    expect(
      () => SkinSpec.fromJson({...raw, 'opacity': .2}),
      throwsFormatException,
    );
    expect(
      () => SkinSpec.fromJson({
        ...raw,
        'colors': {...raw['colors'] as Map, 'muted': '#111111'},
      }),
      throwsFormatException,
    );
    expect(() => SkinSpec.decode('a' * 65537), throwsFormatException);
  });
  test('design template and Markdown tables generate locally', () {
    expect(SkinSpec.fromDesign(skinDesignTemplate).name, '我的曜黑');
    final skin = SkinSpec.fromDesign(
      '# Paper\n| name | Paper |\n| mode | light |\n| radius | 8 |',
    );
    expect(skin.light, true);
    expect(skin.radius, 8);
    expect(() => SkinSpec.fromDesign('想要一个蓝色的主题'), throwsFormatException);
    expect(
      SkinSpec.fromDesign('```seewow-skin\n${builtInSkins[2].encode()}\n```')
          .glass,
      true,
    );
  });
  test('saved custom skin restores tokens, library and typography', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-skin-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
    final skin = communityExamples.last;
    WowSkin.I.use(skin, install: true);
    await WowSkin.I.save();
    WowSkin.I.reset();
    // Snapshot the intended saved state before the queued reset overwrites it.
    await WowSkin.I.save();
    final file = File('${dir.path}/SeeWow/skin.json');
    await file.writeAsString(
      jsonEncode({
        'version': 2,
        'skin': skin.toJson(),
        'installed': [skin.toJson()],
      }),
    );
    await WowSkin.I.load();
    expect(WowSkin.I.spec.encode(), skin.encode());
    expect(WowSkin.I.fontId, WowFontId.editorial);
    expect(WowSkin.I.installed.map((s) => s.name), contains(skin.name));
    WowSkin.I.reset();
    await WowSkin.I.save();
    await dir.delete(recursive: true);
  });
  test(
    'AI skin generation sends only document and validates model output',
    () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var documentSent = false;
      server.listen((req) async {
        expect(req.headers.value('Authorization'), 'Bearer test-key');
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        expect(body['model'], 'theme-model');
        final messages = body['messages'] as List;
        expect(messages.length, 2);
        expect(messages.last['content'], '# design\n冷色玻璃');
        expect(body.containsKey('catalog'), false);
        documentSent = true;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': builtInSkins[2].encode()},
              },
            ],
          }),
        );
        await req.response.close();
      });
      try {
        final result = await SkinGenerator.generate(
          '# design\n冷色玻璃',
          endpoint: 'http://127.0.0.1:${server.port}/chat',
          model: 'theme-model',
          readSecret: (_) async => 'test-key',
        );
        expect(result.glass, true);
        expect(documentSent, true);
      } finally {
        await server.close(force: true);
      }
    },
  );
}
