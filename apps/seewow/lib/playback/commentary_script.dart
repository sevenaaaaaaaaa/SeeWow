import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One spoken remark and the moment it belongs to.
class CommentarySegment {
  const CommentarySegment({required this.at, required this.text, this.file});
  final double at;
  final String text;

  /// Synthesised audio, filled in lazily; null means "not made yet".
  final File? file;

  CommentarySegment withFile(File file) =>
      CommentarySegment(at: at, text: text, file: file);
}

/// Parses the model's JSON script into bounded, ordered segments.
///
/// A language model will sometimes wrap the array in prose or a fence, emit a
/// negative timestamp, or stack two remarks on the same second. None of that is
/// allowed to reach the player: anything unusable is dropped here.
List<CommentarySegment> parseCommentaryScript(
  String raw, {
  required double duration,
  double minimumGap = 8,
  int maxLength = 400,
}) {
  if (duration <= 0) return const [];
  final start = raw.indexOf('[');
  final end = raw.lastIndexOf(']');
  if (start < 0 || end <= start) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(raw.substring(start, end + 1));
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final candidates = <CommentarySegment>[];
  for (final entry in decoded.whereType<Map>()) {
    final at = (entry['at'] ?? entry['time'] ?? entry['t']);
    final seconds = at is num
        ? at.toDouble()
        : double.tryParse(at?.toString() ?? '');
    final text = (entry['text'] ?? entry['line'] ?? entry['content'] ?? '')
        .toString()
        .trim();
    if (seconds == null ||
        !seconds.isFinite ||
        seconds < 0 ||
        seconds > duration ||
        text.isEmpty ||
        text.length > maxLength) {
      continue;
    }
    candidates.add(CommentarySegment(at: seconds, text: text));
  }
  candidates.sort((a, b) => a.at.compareTo(b.at));
  final spaced = <CommentarySegment>[];
  for (final segment in candidates) {
    if (spaced.isNotEmpty && segment.at - spaced.last.at < minimumGap) {
      continue;
    }
    spaced.add(segment);
  }
  return spaced;
}

/// Duration of a PCM WAV file, read from its headers.
///
/// media_kit reports duration asynchronously and only after playback starts;
/// the commentary scheduler needs the length up front to know how long to duck
/// the film, so the header is read directly.
Future<double> wavDurationSeconds(File file) async {
  try {
    return wavDurationFromBytes(await file.readAsBytes());
  } catch (_) {
    return 0;
  }
}

double wavDurationFromBytes(Uint8List bytes) {
  if (bytes.length < 44) return 0;
  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return 0;
  int offset = 12;
  var byteRate = 0;
  var dataSize = 0;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size =
        bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    if (size < 0) return 0;
    if (id == 'fmt ' && offset + 20 <= bytes.length) {
      byteRate =
          bytes[offset + 16] |
          (bytes[offset + 17] << 8) |
          (bytes[offset + 18] << 16) |
          (bytes[offset + 19] << 24);
    } else if (id == 'data') {
      dataSize = size;
      break;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  if (byteRate <= 0 || dataSize <= 0) return 0;
  return dataSize / byteRate;
}
