import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/playback/audio_capture.dart';
import 'package:seewow/playback/frame_bookmarks.dart';
import 'package:seewow/playback/playback_preferences.dart';
import 'package:seewow/playback/playback_window.dart';
import 'package:seewow/playback/voice_translation.dart';
import 'package:seewow/metadata/metadata_transport.dart';

Uint8List wavFixture({
  double seconds = 1,
  double amplitude = .5,
  int rate = 16000,
}) {
  final count = (rate * seconds).round();
  final bytes = Uint8List(44 + count * 2), data = ByteData(44 + count * 2);
  void tag(int offset, String text) {
    for (var i = 0; i < text.length; i++)
      data.setUint8(offset + i, text.codeUnitAt(i));
  }

  tag(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, count * 2, Endian.little);
  for (var i = 0; i < count; i++)
    data.setInt16(
      44 + i * 2,
      (math.sin(i * 440 * 2 * math.pi / rate) * 32767 * amplitude).round(),
      Endian.little,
    );
  bytes.setAll(0, data.buffer.asUint8List());
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-playback-test-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  MediaItem media({bool aiAllowed = true}) => MediaItem(
    id: 'a',
    sourceId: 'private',
    kind: MediaKind.movie,
    title: '影片',
    locator: '/PRIVATE/video.mkv',
    aiAllowed: aiAllowed,
    httpHeaders: {'Authorization': 'SOURCE_SECRET'},
  );
  test('AB points validate order, clear and restart without accepting an empty interval', () {
    final loop = AbLoop();
    loop.mark(2);
    expect(loop.enabled, isFalse);
    expect(() => loop.mark(2.2), throwsFormatException);
    expect(loop.a, 2);
    expect(loop.b, isNull);
    loop.mark(4);
    expect(loop.enabled, isTrue);
    loop.mark(8);
    expect(loop.a, 8);
    expect(loop.b, isNull);
    expect(() => loop.mark(double.nan), throwsFormatException);
    loop.clear();
    expect(loop.a, isNull);
    expect(loop.enabled, isFalse);
    expect(playbackTime(3662), '1:01:02');
  });
  test('PCM loudness follows actual samples and rejects malformed or oversized audio', () {
    final silent = WavAudio.parse(wavFixture(amplitude: 0));
    final quiet = WavAudio.parse(wavFixture(amplitude: .05));
    final loud = WavAudio.parse(wavFixture(amplitude: .8));
    expect(silent.levelAt(.3), 0);
    expect(loud.levelAt(.3), greaterThan(quiet.levelAt(.3)));
    expect(loud.levelAt(.3, volume: 0), 0);
    expect(loud.duration, 1);
    expect(
      () => WavAudio.parse(wavFixture(seconds: 10)),
      throwsFormatException,
    );
    final bad = wavFixture();
    ByteData.sublistView(bad).setUint32(40, 0xffffffff, Endian.little);
    expect(() => WavAudio.parse(bad), throwsFormatException);
    expect(
      () => WavAudio.parse(Uint8List.fromList(utf8.encode('<script>'))),
      throwsFormatException,
    );
  });
  test('frame bookmarks serialize concurrent saves and contain no source path or credentials', () async {
    final store = FrameBookmarks(directory: Directory('${dir.path}/frames'));
    final png = await File('assets/branding/tmdb.png').readAsBytes();
    final saved = await Future.wait([
      store.add(media(), 3, png, note: '亮点'),
      store.add(media(), 4, png),
    ]);
    final list = await store.list(itemId: 'a');
    expect(list, hasLength(2));
    final raw = await File('${dir.path}/frames/index.json').readAsString();
    expect(raw, isNot(contains('SOURCE_SECRET')));
    expect(raw, isNot(contains('/PRIVATE')));
    final reload = FrameBookmarks(directory: Directory('${dir.path}/frames'));
    expect((await reload.list()).map((f) => f.seconds), containsAll([3, 4]));
    await reload.remove(saved.first);
    expect(await File(await reload.path(saved.first)).exists(), isFalse);
    expect(await File(await reload.path(saved.last)).exists(), isTrue);
    expect(await reload.list(), hasLength(1));
  });
  test('invalid frame data does not poison later saves or escape the owned directory', () async {
    final store = FrameBookmarks(directory: dir);
    await expectLater(
      store.add(media(), -1, Uint8List(0)),
      throwsFormatException,
    );
    await expectLater(
      store.add(media(), 1, Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(await store.list(), isEmpty);
    final png = await File('assets/branding/tmdb.png').readAsBytes();
    await store.add(media(), 2, png);
    expect(await store.list(), hasLength(1));
    await expectLater(
      store.path(
        FrameBookmark(
          id: '../outside',
          itemId: 'a',
          title: 'a',
          seconds: 0,
          createdAt: DateTime.now(),
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'voice adapter sends only bounded audio, time and selected language',
    () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      final wav = wavFixture(), calls = <Map>[];
      server.listen((r) async {
        expect(r.headers.value('Authorization'), 'Bearer VOICE_KEY');
        final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
        calls.add(body);
        r.response.write(
          jsonEncode({
            'target_language': 'ja-JP',
            'voice_preserved': true,
            'audio_base64': base64Encode(wav),
            'text': '日本語',
          }),
        );
        await r.response.close();
      });
      final client = VoiceTranslationClient(
        VoiceTranslationConfig(
          endpoint: 'http://127.0.0.1:${server.port}/voice',
          model: 'fixture',
          language: 'ja-JP',
        ),
        token: 'VOICE_KEY',
      );
      addTearDown(client.close);
      final result = await client.translate(media(), WavAudio.parse(wav), 42);
      expect(result.text, '日本語');
      expect(result.audio.duration, 1);
      expect(calls.single['preserve_voice'], isTrue);
      expect(calls.single['source_at_ms'], 42000);
      expect(jsonEncode(calls), isNot(contains('SOURCE_SECRET')));
      expect(jsonEncode(calls), isNot(contains('/PRIVATE')));
      await expectLater(
        client.translate(media(aiAllowed: false), WavAudio.parse(wav), 0),
        throwsFormatException,
      );
      expect(calls, hasLength(1));
    },
  );
  test('voice adapter rejects another language, missing voice claim, links and duration drift', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    final wav = wavFixture();
    var mode = 0;
    server.listen((r) async {
      await r.drain<void>();
      r.response.write(
        jsonEncode({
          'target_language': mode == 0 ? 'ru-RU' : 'zh-CN',
          'voice_preserved': mode != 1,
          if (mode == 2)
            'audio_url': 'https://never-fetch.test/audio.wav'
          else
            'audio_base64': base64Encode(
              mode == 3 ? wavFixture(seconds: 2) : wav,
            ),
        }),
      );
      await r.response.close();
    });
    final client = VoiceTranslationClient(
      VoiceTranslationConfig(
        endpoint: 'http://127.0.0.1:${server.port}/voice',
        model: 'fixture',
      ),
    );
    addTearDown(client.close);
    for (mode = 0; mode < 4; mode++)
      await expectLater(
        client.translate(media(), WavAudio.parse(wav), 0),
        throwsFormatException,
      );
  });
  test('cancel voice request invalidates its pending result', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    final arrived = Completer<void>();
    server.listen((r) async {
      await r.drain<void>();
      arrived.complete();
    });
    final client = VoiceTranslationClient(
      VoiceTranslationConfig(
        endpoint: 'http://127.0.0.1:${server.port}/voice',
        model: 'fixture',
      ),
    );
    final result = expectLater(
      client.translate(media(), WavAudio.parse(wavFixture()), 0),
      throwsA(isA<MetadataCancelled>()),
    );
    await arrived.future;
    client.close();
    await result;
  });
  test(
    'desktop fullscreen and mini player restore prior bounds and topmost state',
    () async {
      final calls = <MethodCall>[];
      var full = false;
      final window = PlaybackWindow();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'getBounds')
              return {'x': 10.0, 'y': 20.0, 'width': 1000.0, 'height': 700.0};
            if (call.method == 'isFullScreen') return full;
            if (call.method == 'isAlwaysOnTop') return false;
            if (call.method == 'setFullScreen') {
              full = call.arguments['isFullScreen'];
              if (full)
                window.onWindowEnterFullScreen();
              else
                window.onWindowLeaveFullScreen();
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('window_manager'),
              null,
            ),
      );
      await window.begin();
      expect(full, isTrue);
      await window.toggleMini();
      expect(window.mini, isTrue);
      expect(full, isFalse);
      await window.toggleMini();
      expect(window.mini, isFalse);
      await window.close();
      expect(full, isFalse);
      expect(
        calls
            .where((c) => c.method == 'setAlwaysOnTop')
            .map((c) => c.arguments['isAlwaysOnTop']),
        containsAllInOrder([true, false]),
      );
      expect(calls.where((c) => c.method == 'setBounds'), isNotEmpty);
    },
  );
}
