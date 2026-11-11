import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import '../domain/media_item.dart';
import '../metadata/metadata_transport.dart';
import 'playback_preferences.dart';

class WavAudio {
  WavAudio._(
    this.bytes,
    this.dataOffset,
    this.dataLength,
    this.sampleRate,
    this.channels,
  );
  final Uint8List bytes;
  final int dataOffset, dataLength, sampleRate, channels;
  double get duration => dataLength / (sampleRate * channels * 2);
  static WavAudio parse(Uint8List bytes, {double maxSeconds = 8.5}) {
    if (bytes.length < 44 ||
        bytes.length > 2 * 1024 * 1024 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE')
      throw const FormatException('需要不超过 2 MiB 的 PCM WAV 音频');
    final data = ByteData.sublistView(bytes);
    int? rate, channels, offset, length;
    var cursor = 12, chunks = 0;
    while (cursor + 8 <= bytes.length && chunks++ < 128) {
      final tag = String.fromCharCodes(bytes.sublist(cursor, cursor + 4));
      final count = data.getUint32(cursor + 4, Endian.little),
          start = cursor + 8;
      if (count > bytes.length - start)
        throw const FormatException('WAV 数据长度无效');
      if (tag == 'fmt ') {
        if (count < 16) throw const FormatException('WAV 格式头无效');
        final format = data.getUint16(start, Endian.little),
            bits = data.getUint16(start + 14, Endian.little);
        final pcm =
            format == 1 ||
            (format == 65534 &&
                count >= 40 &&
                data.getUint32(start + 24, Endian.little) == 1);
        channels = data.getUint16(start + 2, Endian.little);
        rate = data.getUint32(start + 4, Endian.little);
        if (!pcm ||
            bits != 16 ||
            channels < 1 ||
            channels > 2 ||
            rate < 8000 ||
            rate > 48000 ||
            data.getUint16(start + 12, Endian.little) != channels * 2)
          throw const FormatException('WAV 需为 8–48 kHz、16 位、单／双声道 PCM');
      }
      if (tag == 'data') {
        offset = start;
        length = count;
      }
      cursor = start + count + count % 2;
    }
    if (rate == null ||
        channels == null ||
        offset == null ||
        length == null ||
        length == 0 ||
        length % (channels * 2) != 0)
      throw const FormatException('WAV 缺少有效音频数据');
    final result = WavAudio._(bytes, offset, length, rate, channels);
    if (result.duration > maxSeconds || result.duration < .05)
      throw const FormatException('音频时长超出单段范围');
    return result;
  }

  double levelAt(double seconds, {double volume = 100}) {
    if (volume <= 0) return 0;
    final first = (seconds.clamp(0, duration) * sampleRate).floor() * channels;
    final count = math.min(
      (sampleRate * .08).round() * channels,
      dataLength ~/ 2 - first,
    );
    if (count <= 0) return 0;
    final data = ByteData.sublistView(bytes);
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final s =
          data.getInt16(dataOffset + (first + i) * 2, Endian.little) / 32768;
      sum += s * s;
    }
    if (sum <= 0) return 0;
    return normalizedLoudness(
          '${20 * math.log(math.sqrt(sum / count)) / math.ln10}',
          volume: volume,
        ) ??
        0;
  }
}

/// Independent audio-only decoder; never changes the main player's filters/output.
class AudioCapture {
  int _revision = 0;
  Completer<void>? _pending;
  Future<void> Function()? _closeActive;
  Future<void> cancel() async {
    _revision++;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted)
      pending.completeError(MetadataCancelled());
    final close = _closeActive;
    _closeActive = null;
    await close?.call();
  }

  Future<WavAudio> capture(MediaItem source, double at, double seconds) async {
    if (!at.isFinite ||
        at < 0 ||
        !seconds.isFinite ||
        seconds < .5 ||
        seconds > 8)
      throw const FormatException('音频采样范围无效');
    await cancel();
    final ticket = _revision;
    final dir = await Directory.systemTemp.createTemp('seewow-audio-');
    final file = File('${dir.path}/sample.wav');
    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: 2 * 1024 * 1024),
    );
    final native = player.platform;
    Future<void>? disposed;
    Future<void> close() => disposed ??= player.dispose();
    _closeActive = close;
    final done = Completer<void>();
    _pending = done;
    final finished = done.future
        .timeout(const Duration(seconds: 20))
        .then<Object?>((_) => null, onError: (Object e) => e);
    final completion = player.stream.completed.listen((v) {
      if (v && !done.isCompleted) done.complete();
    });
    final errors = player.stream.error.listen((_) {
      if (!done.isCompleted)
        done.completeError(const FormatException('此音频暂不能采样，请检查格式或来源连接'));
    });
    try {
      if (native is! NativePlayer)
        throw const FormatException('当前播放器不支持本机音频采样');
      await native.setProperty('vid', 'no');
      await native.setProperty('ao', 'pcm');
      await native.setProperty('ao-pcm-file', file.path);
      await native.setProperty('audio-format', 's16');
      await native.setProperty('audio-channels', 'mono');
      await native.setProperty('audio-samplerate', '16000');
      await player.open(
        Media(
          source.locator,
          httpHeaders: source.httpHeaders,
          start: Duration(milliseconds: (at * 1000).round()),
          end: Duration(milliseconds: ((at + seconds) * 1000).round()),
        ),
      );
      final failure = await finished;
      if (failure != null) throw failure;
      await close();
      if (ticket != _revision) throw MetadataCancelled();
      if (!await file.exists() || await file.length() > 2 * 1024 * 1024)
        throw const FormatException('当前解码器未提供有界的 PCM 音频');
      return WavAudio.parse(await file.readAsBytes(), maxSeconds: seconds + .5);
    } catch (e) {
      if (ticket != _revision || e is MetadataCancelled)
        throw MetadataCancelled();
      if (e is FormatException) rethrow;
      throw const FormatException('音频采样失败或超时，原片播放未改变');
    } finally {
      if (!done.isCompleted) done.completeError(MetadataCancelled());
      await completion.cancel();
      await errors.cancel();
      await close();
      if (_closeActive == close) _closeActive = null;
      if (identical(_pending, done)) _pending = null;
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}
