import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'commentary_script.dart';

/// What an export produced, so the UI can say something true about it.
class CommentaryExportResult {
  const CommentaryExportResult({
    required this.track,
    required this.manifest,
    required this.segments,
    required this.duration,
  });
  final File track, manifest;
  final int segments;
  final double duration;
}

/// A PCM WAV's format plus its sample bytes.
class _Pcm {
  const _Pcm({
    required this.sampleRate,
    required this.channels,
    required this.bits,
    required this.data,
  });
  final int sampleRate, channels, bits;
  final Uint8List data;
}

/// Parses only what is needed: `fmt ` says how to read `data`.
_Pcm? _decodeWav(Uint8List bytes) {
  if (bytes.length < 44) return null;
  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
  var offset = 12;
  var sampleRate = 0, channels = 0, bits = 0;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = _uint32(bytes, offset + 4);
    if (size < 0 || offset + 8 + size > bytes.length) return null;
    if (id == 'fmt ' && size >= 16) {
      channels = _uint16(bytes, offset + 10);
      sampleRate = _uint32(bytes, offset + 12);
      bits = _uint16(bytes, offset + 22);
    } else if (id == 'data') {
      if (sampleRate <= 0 || channels <= 0 || bits != 16) return null;
      return _Pcm(
        sampleRate: sampleRate,
        channels: channels,
        bits: bits,
        data: Uint8List.sublistView(bytes, offset + 8, offset + 8 + size),
      );
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

int _uint16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// Turns the spoken segments into one offline track: silence where the film
/// plays, speech where a remark belongs.
///
/// Every segment must already be a 16-bit WAV from the same engine; the system
/// TTS produces exactly that per platform, and a mismatch is reported instead of
/// being resampled into something that sounds wrong.
Future<CommentaryExportResult> exportCommentaryTrack({
  required List<CommentarySegment> segments,
  required Directory directory,
  String baseName = 'commentary',
  DateTime? now,
}) async {
  if (segments.isEmpty) throw const FormatException('没有可导出的解说脚本');
  if (!await directory.exists()) await directory.create(recursive: true);
  final stamp = (now ?? DateTime.now())
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-');
  final decodeds = <_Pcm>[];
  final missing = <int>[];
  for (var i = 0; i < segments.length; i++) {
    final file = segments[i].file;
    if (file == null) {
      missing.add(i);
      continue;
    }
    if (!await file.exists()) {
      throw FormatException('第 ${i + 1} 段解说音频文件已不存在，请重新生成');
    }
    final pcm = _decodeWav(await file.readAsBytes());
    if (pcm == null) {
      throw FormatException('第 ${i + 1} 段解说的音频不是 16 位 PCM WAV，无法合成音轨');
    }
    decodeds.add(pcm);
  }
  if (missing.isNotEmpty) {
    throw FormatException('有 ${missing.length} 段解说还没有合成音频，请先生成音频再导出');
  }
  final sampleRate = decodeds.first.sampleRate;
  final mismatch = decodeds.indexWhere((pcm) => pcm.sampleRate != sampleRate);
  if (mismatch >= 0) {
    throw FormatException(
      '第 ${mismatch + 1} 段解说的采样率与其余段不一致（${decodeds[mismatch].sampleRate} vs $sampleRate），请重新生成',
    );
  }

  final out = BytesBuilder();
  var writtenSamples = 0;
  for (var i = 0; i < segments.length; i++) {
    final mono = _toMono(decodeds[i]);
    final start = (segments[i].at * sampleRate).round();
    if (start > writtenSamples) {
      out.add(Uint8List((start - writtenSamples) * 2));
      writtenSamples = start;
    }
    out.add(mono);
    writtenSamples += mono.length ~/ 2;
  }
  final pcmBytes = out.takeBytes();
  final wav = _encodeWav(pcmBytes, sampleRate);
  final track = File('${directory.path}/$baseName-$stamp.wav');
  await track.writeAsBytes(wav, flush: true);
  final manifest = File('${directory.path}/$baseName-$stamp.json');
  await manifest.writeAsString(
    JsonEncoder.withIndent('  ').convert({
      'format': 'seewow-commentary/1',
      'generatedAt': (now ?? DateTime.now()).toIso8601String(),
      'duration': writtenSamples / sampleRate,
      'segments': [
        for (var i = 0; i < segments.length; i++)
          {'at': segments[i].at, 'text': segments[i].text},
      ],
    }),
    flush: true,
  );
  return CommentaryExportResult(
    track: track,
    manifest: manifest,
    segments: segments.length,
    duration: writtenSamples / sampleRate,
  );
}

/// Duplicated mono channels are averaged instead of dropped, so a stereo file
/// does not lose half its level.
Uint8List _toMono(_Pcm pcm) {
  if (pcm.channels == 1) return pcm.data;
  final frames = pcm.data.length ~/ (2 * pcm.channels);
  final mono = Uint8List(frames * 2);
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0;
    for (var channel = 0; channel < pcm.channels; channel++) {
      sum += _int16(pcm.data, (frame * pcm.channels + channel) * 2);
    }
    final value = (sum / pcm.channels).round().clamp(-32768, 32767);
    mono[frame * 2] = value & 0xFF;
    mono[frame * 2 + 1] = (value >> 8) & 0xFF;
  }
  return mono;
}

int _int16(Uint8List bytes, int offset) {
  final value = bytes[offset] | (bytes[offset + 1] << 8);
  return value >= 0x8000 ? value - 0x10000 : value;
}

Uint8List _encodeWav(Uint8List pcm, int sampleRate) {
  final header = BytesBuilder();
  void string(String value) => header.add(value.codeUnits);
  void uint16(int value) => header.add([value & 0xFF, (value >> 8) & 0xFF]);
  void uint32(int value) => header.add([
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ]);

  string('RIFF');
  uint32(36 + pcm.length);
  string('WAVE');
  string('fmt ');
  uint32(16);
  uint16(1); // PCM
  uint16(1); // mono
  uint32(sampleRate);
  uint32(sampleRate * 2);
  uint16(2);
  uint16(16);
  string('data');
  uint32(pcm.length);
  header.add(pcm);
  return header.toBytes();
}
