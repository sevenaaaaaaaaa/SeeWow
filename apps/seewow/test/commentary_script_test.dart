import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/commentary_script.dart';

Uint8List _wav({int byteRate = 44100, int dataBytes = 44100 * 3}) {
  final header = BytesBuilder();
  void writeString(String value) => header.add(value.codeUnits);
  void writeUint32(int value) => header.add([
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ]);

  writeString('RIFF');
  writeUint32(36 + dataBytes);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  header.add([1, 0, 1, 0]); // PCM, mono
  writeUint32(byteRate); // sample rate
  writeUint32(byteRate); // byte rate
  header.add([1, 0, 16, 0]);
  writeString('data');
  writeUint32(dataBytes);
  header.add(Uint8List(dataBytes));
  return header.toBytes();
}

void main() {
  group('parseCommentaryScript', () {
    test('parses a clean array', () {
      final segments = parseCommentaryScript(
        '[{"at": 30, "text": "开场"}, {"at": 120, "text": "中段"}]',
        duration: 600,
      );
      expect(segments.length, 2);
      expect(segments.first.at, 30);
      expect(segments.first.text, '开场');
    });

    test('tolerates a fenced block or prose around the array', () {
      final segments = parseCommentaryScript(
        '好的，这是脚本：\n```json\n[{"at": 60, "text": "第一段"}]\n```\n希望合适。',
        duration: 600,
      );
      expect(segments.single.text, '第一段');
    });

    test('drops timestamps outside the film and empty text', () {
      final segments = parseCommentaryScript(
        '[{"at": -5, "text": "负"}, {"at": 900, "text": "超长"}, '
        '{"at": 100, "text": ""}, {"at": 200, "text": "保留"}]',
        duration: 600,
      );
      expect(segments.single.text, '保留');
    });

    test('keeps remarks in order and spaces them out', () {
      final segments = parseCommentaryScript(
        '[{"at": 300, "text": "后"}, {"at": 60, "text": "前"}, '
        '{"at": 63, "text": "太近"}]',
        duration: 600,
      );
      expect(segments.map((s) => s.text), ['前', '后']);
    });

    test('accepts alternate field names from a chatty model', () {
      final segments = parseCommentaryScript(
        '[{"time": "45", "line": "别名"}]',
        duration: 600,
      );
      expect(segments.single.at, 45);
      expect(segments.single.text, '别名');
    });

    test('returns nothing for garbage or an unknown duration', () {
      expect(parseCommentaryScript('no json here', duration: 600), isEmpty);
      expect(parseCommentaryScript('[{"at": 10, "text": "x"}]', duration: 0), isEmpty);
      expect(parseCommentaryScript('[{"at": 10}]', duration: 600), isEmpty);
    });

    test('caps overlong lines instead of speaking them', () {
      final long = 'x' * 500;
      final segments = parseCommentaryScript(
        '[{"at": 10, "text": "$long"}]',
        duration: 600,
      );
      expect(segments, isEmpty);
    });
  });

  group('wavDurationFromBytes', () {
    test('reads duration from the header', () {
      final bytes = _wav(byteRate: 44100, dataBytes: 44100 * 3);
      expect(wavDurationFromBytes(bytes), closeTo(3.0, 0.01));
    });

    test('returns zero for non-WAV input', () {
      expect(wavDurationFromBytes(Uint8List.fromList([1, 2, 3])), 0);
      expect(
        wavDurationFromBytes(Uint8List.fromList(List.filled(100, 65))),
        0,
      );
    });
  });
}
