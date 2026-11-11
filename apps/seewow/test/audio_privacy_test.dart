import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/audio_privacy.dart';
import 'package:seewow/playback/sensitive_content.dart';
import 'package:seewow/domain/media_metadata.dart';
import 'package:seewow/metadata/nfo_reader.dart';

void main() {
  late DateTime date;
  late DailyVolumeMemory memory;
  late AudioPrivacy privacy;
  setUp(() {
    date = DateTime(2026, 11, 12, 23, 59);
    memory = DailyVolumeMemory(now: () => date);
    privacy = AudioPrivacy(memory);
  });
  test('every new player starts silent and output defaults are separate', () {
    expect(privacy.effectiveVolume, 0);
    expect(privacy.unmute(), isTrue);
    expect(privacy.effectiveVolume, 30);
    privacy.selectVolume(90);
    final next = AudioPrivacy(memory);
    expect(next.effectiveVolume, 0);
    next.changeRoute(AudioOutputRoute.headphones);
    next.unmute();
    expect(next.effectiveVolume, 50);
    next.changeRoute(AudioOutputRoute.speaker);
    expect(next.effectiveVolume, 0);
    next.unmute();
    expect(next.effectiveVolume, 30);
  });
  test('quieter volume persists today by route; mute never overwrites it', () {
    privacy.changeRoute(AudioOutputRoute.speaker);
    privacy.selectVolume(12);
    privacy.muted = true;
    expect(memory.initial(AudioOutputRoute.speaker), 12);
    privacy.unmute();
    expect(privacy.effectiveVolume, 12);
    privacy.changeRoute(AudioOutputRoute.headphones);
    privacy.selectVolume(24);
    privacy.changeRoute(AudioOutputRoute.speaker);
    privacy.unmute();
    expect(privacy.effectiveVolume, 12);
    final restored = DailyVolumeMemory(now: () => date)
      ..restore(memory.encode());
    expect(restored.initial(AudioOutputRoute.headphones), 24);
    expect(restored.initial(AudioOutputRoute.speaker), 12);
  });
  test('yesterday, invalid values and future dates never restore gain', () {
    privacy.selectVolume(7);
    final raw = memory.encode();
    date = date.add(const Duration(minutes: 2));
    expect(memory.initial(AudioOutputRoute.speaker), 30);
    memory.restore(raw);
    expect(memory.initial(AudioOutputRoute.speaker), 30);
    memory.restore('{"day":"2026-11-13","speaker":101,"headphones":-2}');
    expect(memory.initial(AudioOutputRoute.headphones), 50);
    memory.restore('{"day":"2099-1-1","speaker":2}');
    expect(memory.initial(AudioOutputRoute.speaker), 30);
    expect(memory.encode(), isNot(contains('2026-11-12')));
  });
  test(
    'a positive detection cannot be bypassed by unmute or volume controls',
    () {
      privacy.unmute();
      privacy.detectSensitive();
      expect(privacy.blocked, isTrue);
      expect(privacy.unmute(), isFalse);
      privacy.selectVolume(100);
      expect(privacy.effectiveVolume, 0);
      privacy.changeRoute(AudioOutputRoute.headphones);
      expect(privacy.effectiveVolume, 0);
      expect(privacy.unmute(), isTrue);
      expect(privacy.effectiveVolume, 50);
      privacy.changeRoute(AudioOutputRoute.unknown);
      privacy.unmute();
      expect(privacy.effectiveVolume, 0);
      expect(privacy.sensitive, isTrue);
    },
  );
  test('NSFW detection on confirmed headphones preserves ongoing audio', () {
    privacy.changeRoute(AudioOutputRoute.headphones);
    privacy.unmute();
    privacy.detectSensitive();
    expect(privacy.effectiveVolume, 50);
    privacy.changeRoute(AudioOutputRoute.speaker);
    expect(privacy.effectiveVolume, 0);
  });
  test(
    'only explicit NSFW metadata classifies; titles and mature drama do not',
    () {
      MediaMetadata metadata({bool? adult, List<String> genres = const []}) =>
          MediaMetadata(
            id: 1,
            title: 'Adult life / NSFW title',
            mediaType: 'movie',
            adult: adult,
            genres: genres,
          );
      expect(hasSensitiveMetadata(metadata()), isFalse);
      expect(hasSensitiveMetadata(metadata(genres: ['Drama', '18+'])), isFalse);
      final m = metadata(adult: true);
      expect(hasSensitiveMetadata(MediaMetadata.fromJson(m.toJson())), isTrue);
      expect(hasSensitiveMetadata(metadata(genres: ['NSFW'])), isTrue);
      final nfo = NfoInfo.parse(
        '<movie><title>Test</title><adult>true</adult></movie>',
      );
      expect(
        nfo.asMetadata(fallbackTitle: '', mediaType: 'movie').adult,
        isTrue,
      );
    },
  );
}
