import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/playback/audio_capture.dart';
import 'package:seewow/playback/audio_privacy.dart';
import 'package:seewow/playback/dubbing_controller.dart';
import 'package:seewow/playback/voice_translation.dart';

void main() {
  test(
    'bundled mpv independently captures a bounded WAV and computes actual RMS',
    () async {
      MediaKit.ensureInitialized(libmpv: Platform.environment['SEEWOW_MPV']);
      final capture = AudioCapture();
      final audio = await capture.capture(
        MediaItem(
          id: 'probe',
          sourceId: 'test',
          kind: MediaKind.audio,
          title: 'Sine',
          locator:
              Platform.environment['SEEWOW_PROBE_MEDIA'] ??
              '/tmp/seewow-playback-probe.wav',
        ),
        2,
        2,
      );
      expect(audio.duration, closeTo(2, .15));
      expect(audio.levelAt(.5), greaterThan(.1));
      print(
        'NATIVE_PCM_SECONDS=${audio.duration}; RMS_LEVEL=${audio.levelAt(.5)}',
      );
      await capture.cancel();
    },
    skip: Platform.environment['SEEWOW_NATIVE_PROBE'] != '1',
  );
  test('native buffered dubbing traverses adapter playback and restores original mute state', () async {
    MediaKit.ensureInitialized(libmpv: Platform.environment['SEEWOW_MPV']);
    final privacy = AudioPrivacy(DailyVolumeMemory());
    final video = Player(configuration: const PlayerConfiguration(muted: true)),
        output = Player();
    await (video.platform as NativePlayer).setProperty('ao', 'null');
    await (output.platform as NativePlayer).setProperty('ao', 'null');
    final source = MediaItem(
      id: 'voice-probe',
      sourceId: 'fixture',
      kind: MediaKind.movie,
      title: 'Synthetic sine',
      locator:
          Platform.environment['SEEWOW_PROBE_MEDIA'] ??
          '/tmp/seewow-playback-probe.wav',
    );
    final loaded = video.stream.duration.firstWhere(
      (d) => d.inMilliseconds > 0,
    );
    await video.open(
      Media(source.locator, start: const Duration(seconds: 6)),
      play: false,
    );
    await loaded;
    final server = await HttpServer.bind('127.0.0.1', 0);
    var requests = 0;
    server.listen((r) async {
      final payload = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      requests++;
      r.response.write(
        jsonEncode({
          'target_language': 'zh-CN',
          'voice_preserved': true,
          'audio_base64': payload['source_audio']['base64'],
          'text': '仅验证音频通路的合成测试',
        }),
      );
      await r.response.close();
    });
    final session = DubbingController(
      video: video,
      source: source,
      audioOutput: output,
      effectiveVolume: () => privacy.effectiveVolume,
      client: VoiceTranslationClient(
        VoiceTranslationConfig(
          endpoint: 'http://127.0.0.1:${server.port}/voice',
          model: 'fixture',
        ),
      ),
    );
    final finished = Completer<void>();
    var began = false;
    final playedVolume = Completer<double>();
    final volumeSub = output.stream.playing.listen((playing) async {
      if (playing && !playedVolume.isCompleted) {
        final gain = double.parse(
          await (output.platform as NativePlayer).getProperty('volume'),
        );
        if (!playedVolume.isCompleted) playedVolume.complete(gain);
      }
    });
    session.addListener(() {
      began = began || session.active;
      if (began && !session.active && !finished.isCompleted)
        finished.complete();
    });
    try {
      await session.start();
      await finished.future.timeout(const Duration(seconds: 15));
      expect(session.error, isNull);
      expect(await playedVolume.future.timeout(const Duration(seconds: 2)), 0);
      expect(
        double.parse(
          await (video.platform as NativePlayer).getProperty('volume'),
        ),
        0,
      );
      expect(requests, 1);
      expect(await (video.platform as NativePlayer).getProperty('mute'), 'no');
      print(
        'NATIVE_DUBBING_ADAPTER_REQUESTS=$requests; ORIGINAL_MUTE_RESTORED',
      );
    } finally {
      await volumeSub.cancel();
      await session.close();
      await video.dispose();
      await server.close(force: true);
    }
  }, skip: Platform.environment['SEEWOW_NATIVE_PROBE'] != '1');
}
