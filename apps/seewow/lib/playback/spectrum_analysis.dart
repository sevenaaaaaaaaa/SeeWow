import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_capture.dart';

/// 真正的分频能量：截播放点附近的一帧 PCM，做 FFT，得到每个频段的强度。
///
/// 播放器原本只有一个标量 RMS 电平，[SpectrumShape.bands] 拿它塑形，注释里
/// 也写明「不是频率分析，也不假装是」。这里补上缺的那一步——PCM 本来就在手上
/// （[AudioCapture] 用第二个 mpv 实例落盘 16 kHz 单声道 WAV），差的是分析。
class SpectrumAnalysis {
  const SpectrumAnalysis._();

  /// 归一化基准：满幅正弦 ≈ 0 dB，-60 dB 以下算静音。
  static const double floorDb = -60;

  /// 分析窗口 1024 点 @16 kHz ≈ 64 ms：听得出鼓点，又不把瞬态抹平。
  static const int window = 1024;

  /// 频段：55 Hz 到 7 kHz，按对数分段（低音给得多，符合听觉）。
  static const double lowHz = 55, highHz = 7000;

  static List<double> bands(
    WavAudio audio, {
    required double at,
    int bands = 16,
  }) {
    if (bands <= 0) return const [];
    if (!at.isFinite || at < 0) return List<double>.filled(bands, 0);
    final rate = audio.sampleRate;
    final channels = audio.channels;
    final frames = audio.dataLength ~/ (channels * 2);
    final start = (at * rate).floor();
    if (start >= frames) return List<double>.filled(bands, 0);

    final data = ByteData.sublistView(audio.bytes);
    final re = Float64List(window);
    final im = Float64List(window);
    var energy = 0.0;
    for (var i = 0; i < window; i++) {
      final frame = start + i;
      var s = 0.0;
      if (frame < frames) {
        for (var c = 0; c < channels; c++) {
          s +=
              data.getInt16(
                audio.dataOffset + (frame * channels + c) * 2,
                Endian.little,
              ) /
              32768;
        }
        s /= channels;
      }
      energy += s * s;
      // 不加窗时相邻频段的能量会互相漏，整条频谱会糊成一片。
      re[i] = s * (0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1)));
    }
    if (energy <= 1e-12) return List<double>.filled(bands, 0);

    _fft(re, im);

    final nyquist = rate / 2;
    final top = math.min(highHz, nyquist * .94);
    final low = math.min(lowHz, top / 2);
    final bins = window ~/ 2;
    final result = List<double>.filled(bands, 0);
    for (var b = 0; b < bands; b++) {
      final from = low * math.pow(top / low, b / bands);
      final to = low * math.pow(top / low, (b + 1) / bands);
      final firstBin = math.max(1, (from / nyquist * bins).floor());
      final lastBin = math.min(
        bins,
        math.max(firstBin, (to / nyquist * bins).ceil() - 1),
      );
      var peak = 0.0;
      for (var k = firstBin; k <= lastBin; k++) {
        // 取频段内的峰值而不是均值：底鼓、军鼓这类瞬态不该被邻频稀释。
        final amp = math.sqrt(re[k] * re[k] + im[k] * im[k]) / (window / 4);
        if (amp > peak) peak = amp;
      }
      final db = 20 * math.log(peak + 1e-9) / math.ln10;
      result[b] = ((db - floorDb) / -floorDb).clamp(0.0, 1.0);
    }
    return result;
  }

  /// 就地基 2 迭代 FFT；长度必须是 2 的幂（这里是 1024）。
  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wr = math.cos(angle), wi = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        final half = len >> 1;
        for (var k = 0; k < half; k++) {
          final ur = re[i + k], ui = im[i + k];
          final xr = re[i + k + half], xi = im[i + k + half];
          final vr = xr * cr - xi * ci;
          final vi = xr * ci + xi * cr;
          re[i + k] = ur + vr;
          im[i + k] = ui + vi;
          re[i + k + half] = ur - vr;
          im[i + k + half] = ui - vi;
          final nextCr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = nextCr;
        }
      }
    }
  }
}
