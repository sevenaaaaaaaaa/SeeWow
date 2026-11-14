import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/commentary_export.dart';
import 'package:seewow/playback/commentary_script.dart';

Uint8List _wav({
  int sampleRate = 8000,
  int channels = 1,
  int frames = 2000,
  int value = 1000,
  int bits = 16,
}) {
  final bytesPerSample = bits ~/ 8;
  final dataBytes = frames * channels * bytesPerSample;
  final builder = BytesBuilder();
  void text(String value) => builder.add(value.codeUnits);
  void uint32(int value) => builder.add([
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ]);
  void uint16(int value) => builder.add([value & 0xFF, (value >> 8) & 0xFF]);

  text('RIFF');
  uint32(36 + dataBytes);
  text('WAVE');
  text('fmt ');
  uint32(16);
  uint16(1);
  uint16(channels);
  uint32(sampleRate);
  uint32(sampleRate * channels * bytesPerSample);
  uint16(channels * bytesPerSample);
  uint16(bits);
  text('data');
  uint32(dataBytes);
  for (var i = 0; i < frames * channels; i++) {
    if (bits == 16) {
      builder.add([value & 0xFF, (value >> 8) & 0xFF]);
    } else {
      builder.add([value & 0xFF]);
    }
  }
  return builder.toBytes();
}

int _int16(Uint8List bytes, int offset) {
  final raw = bytes[offset] | (bytes[offset + 1] << 8);
  return raw >= 0x8000 ? raw - 0x10000 : raw;
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('seewow-commentary-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('lays the remarks on a silent timeline', () async {
    final first = File('${directory.path}/a.wav');
    await first.writeAsBytes(_wav());
    final second = File('${directory.path}/b.wav');
    await second.writeAsBytes(_wav());
    final result = await exportCommentaryTrack(
      segments: [
        CommentarySegment(at: 0.5, text: '第一段', file: first),
        CommentarySegment(at: 2.0, text: '第二段', file: second),
      ],
      directory: directory,
      now: DateTime.utc(2026, 11, 14, 12, 0, 0),
    );
    expect(result.segments, 2);
    // 2.0 s of silence-plus-speech before the last remark, then its 0.25 s.
    expect(result.duration, closeTo(2.25, 0.001));
    final bytes = await result.track.readAsBytes();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(bytes.length, 44 + (2.25 * 8000 * 2).round());
    // Before the first remark the track must be silent.
    expect(bytes.sublist(44, 44 + 800).every((b) => b == 0), isTrue);
    // The first remark starts at 0.5 s, which is byte 8000.
    expect(_int16(bytes, 44 + 8000), 1000);
    final manifest = jsonDecode(await result.manifest.readAsString()) as Map;
    expect(manifest['format'], 'seewow-commentary/1');
    expect((manifest['segments'] as List).length, 2);
    expect((manifest['segments'] as List).first['text'], '第一段');
    expect(result.manifest.path, endsWith('.json'));
    expect(result.track.path, contains('2026-11-14T12-00-00'));
  });

  test('averages stereo into mono instead of dropping a channel', () async {
    final file = File('${directory.path}/stereo.wav');
    // frame 0: L=1000, R=3000 -> 2000; frame 1: L=-1000, R=-1000 -> -1000.
    final builder = BytesBuilder();
    void text(String value) => builder.add(value.codeUnits);
    void uint32(int value) => builder.add([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
    void uint16(int value) => builder.add([value & 0xFF, (value >> 8) & 0xFF]);
    const dataBytes = 8;
    text('RIFF');
    uint32(36 + dataBytes);
    text('WAVE');
    text('fmt ');
    uint32(16);
    uint16(1);
    uint16(2);
    uint32(8000);
    uint32(32000);
    uint16(4);
    uint16(16);
    text('data');
    uint32(dataBytes);
    for (final sample in [1000, 3000, -1000, -1000]) {
      final value = sample < 0 ? sample + 0x10000 : sample;
      builder.add([value & 0xFF, (value >> 8) & 0xFF]);
    }
    await file.writeAsBytes(builder.toBytes());
    final result = await exportCommentaryTrack(
      segments: [CommentarySegment(at: 0, text: '立体声', file: file)],
      directory: directory,
    );
    final bytes = await result.track.readAsBytes();
    expect(_int16(bytes, 44), 2000);
    expect(_int16(bytes, 46), -1000);
    expect(result.duration, closeTo(2 / 8000, 0.0001));
  });

  test('refuses a segment whose audio was never synthesised', () async {
    expect(
      () => exportCommentaryTrack(
        segments: [const CommentarySegment(at: 1, text: '无声')],
        directory: directory,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('refuses audio that is not 16-bit PCM', () async {
    final file = File('${directory.path}/eight.wav');
    await file.writeAsBytes(_wav(bits: 8, value: 1));
    expect(
      () => exportCommentaryTrack(
        segments: [CommentarySegment(at: 0, text: '八位', file: file)],
        directory: directory,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('refuses mixed sample rates instead of resampling badly', () async {
    final a = File('${directory.path}/8k.wav');
    await a.writeAsBytes(_wav(sampleRate: 8000));
    final b = File('${directory.path}/16k.wav');
    await b.writeAsBytes(_wav(sampleRate: 16000));
    expect(
      () => exportCommentaryTrack(
        segments: [
          CommentarySegment(at: 0, text: '八', file: a),
          CommentarySegment(at: 1, text: '十六', file: b),
        ],
        directory: directory,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('an empty script is not an export', () async {
    expect(
      () => exportCommentaryTrack(segments: const [], directory: directory),
      throwsA(isA<FormatException>()),
    );
  });
}
