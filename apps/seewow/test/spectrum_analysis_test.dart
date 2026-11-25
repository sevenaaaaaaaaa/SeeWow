import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/audio_capture.dart';
import 'package:seewow/playback/spectrum_analysis.dart';

/// 16 kHz / 16 位 / 单声道 WAV：和 AudioCapture 落盘出来的格式一致。
Uint8List wav(List<double> samples, {int rate = 16000}) {
  final n = samples.length;
  final bytes = ByteData(44 + n * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + n * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    bytes.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

List<double> tone(
  double hz, {
  int rate = 16000,
  double seconds = 1,
  double amp = .9,
}) => List<double>.generate(
  (rate * seconds).round(),
  (i) => amp * math.sin(2 * math.pi * hz * i / rate),
);

void main() {
  test('1 kHz 正弦的能量落在中频段，低频与高频都安静', () {
    final audio = WavAudio.parse(wav(tone(1000)));
    final bands = SpectrumAnalysis.bands(audio, at: .25, bands: 16);

    expect(bands.length, 16);
    final peak = bands.indexOf(bands.reduce(math.max));
    expect(
      peak,
      inInclusiveRange(8, 11),
      reason: '1 kHz 应落在 55–7000 Hz 的对数第 8–11 段',
    );
    expect(bands[peak], greaterThan(.5), reason: '满幅正弦要有可观的能量');
    expect(
      bands.take(5).every((v) => v < .3),
      isTrue,
      reason: '200 Hz 以下不该有能量',
    );
    expect(
      bands.skip(13).every((v) => v < .35),
      isTrue,
      reason: '3 kHz 以上不该有能量',
    );
  });

  test('静音是零，不是一条随机噪声', () {
    final audio = WavAudio.parse(wav(List<double>.filled(16000, 0)));
    expect(SpectrumAnalysis.bands(audio, at: .3), everyElement(0));
  });

  test('播放点越过采样窗口时返回零，不越界读', () {
    final audio = WavAudio.parse(wav(tone(440)));
    expect(SpectrumAnalysis.bands(audio, at: 9), everyElement(0));
    expect(SpectrumAnalysis.bands(audio, at: -1), everyElement(0));
  });

  test('幅度变小，同一频段能量跟着变小', () {
    final loud = SpectrumAnalysis.bands(
      WavAudio.parse(wav(tone(1000))),
      at: .3,
    );
    final quiet = SpectrumAnalysis.bands(
      WavAudio.parse(wav(tone(1000, amp: .09))),
      at: .3,
    );
    final loudPeak = loud.reduce(math.max), quietPeak = quiet.reduce(math.max);
    expect(quietPeak, lessThan(loudPeak));
    expect(quietPeak, greaterThan(0));
  });

  test('段数为零时不返回半个数组', () {
    final audio = WavAudio.parse(wav(tone(1000)));
    expect(SpectrumAnalysis.bands(audio, at: .3, bands: 0), isEmpty);
  });
}
