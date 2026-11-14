import 'dart:io';

import 'package:flutter/foundation.dart';

/// Text-to-speech through the operating system's own voice.
///
/// The app ships no TTS engine and needs no API key for this: macOS has `say`,
/// Windows has SAPI through PowerShell, and Linux usually has `espeak-ng`.
/// When none of them exist the feature reports itself unavailable instead of
/// failing at playback time.
class SpeechSynthesizer {
  SpeechSynthesizer({this.voice = ''});

  /// Optional voice name (`say -v '?'` lists them on macOS).
  final String voice;

  String? _resolved;

  /// `macos`, `windows`, `espeak`, or null when nothing usable exists.
  Future<String?> backend() async {
    if (_resolved != null) return _resolved!.isEmpty ? null : _resolved;
    String found = '';
    try {
      if (Platform.isMacOS) {
        if (await _probe('say', ['-v', '?'])) found = 'macos';
      } else if (Platform.isWindows) {
        // Windows PowerShell has no --version flag; a no-op command is the
        // honest probe, since the exit code is the only reliable signal.
        if (await _probe('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'exit 0',
        ])) {
          found = 'windows';
        }
      } else if (Platform.isLinux) {
        for (final candidate in ['espeak-ng', 'espeak']) {
          if (await _probe(candidate, ['--voices'])) {
            found = 'espeak:$candidate';
            break;
          }
        }
      }
    } catch (error) {
      debugPrint('tts backend probe failed: $error');
    }
    _resolved = found;
    return found.isEmpty ? null : found;
  }

  /// Exit code zero means the binary exists and can run; a missing binary
  /// throws and is reported as unavailable.
  Future<bool> _probe(String binary, List<String> arguments) async {
    try {
      final result = await Process.run(binary, arguments, runInShell: false);
      return result.exitCode == 0;
    } catch (error) {
      debugPrint('tts probe failed for $binary: $error');
      return false;
    }
  }

  /// Synthesises [text] into a WAV file inside [directory].
  ///
  /// Returns null when the platform has no usable engine; throws when the
  /// engine exists but the text cannot be synthesised.
  Future<File?> synthesize(
    String text, {
    required Directory directory,
    String? languageHint,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final engine = await backend();
    if (engine == null) return null;
    if (!await directory.exists()) await directory.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final wav = File('${directory.path}/commentary-$stamp.wav');
    final raw = File('${directory.path}/commentary-$stamp.raw.aiff');
    try {
      if (engine == 'macos') {
        // `say` writes AIFF; afconvert turns it into the WAV the player wants.
        await Process.run(
          'say',
          [
            if (voice.trim().isNotEmpty) ...['-v', voice.trim()],
            '-o',
            raw.path,
            '--',
            trimmed,
          ],
          runInShell: false,
        );
        if (!await raw.exists() || await raw.length() < 64) {
          throw const FormatException('系统语音没有生成音频');
        }
        await Process.run(
          'afconvert',
          ['-f', 'WAVE', '-d', 'LEI16', raw.path, wav.path],
          runInShell: false,
        );
      } else if (engine.startsWith('espeak')) {
        final binary = engine.split(':').last;
        final code = _espeakVoice(languageHint);
        await Process.run(
          binary,
          ['-v', code, '-w', wav.path, '--', trimmed],
          runInShell: false,
        );
      } else if (engine == 'windows') {
        final escaped = trimmed.replaceAll("'", "''").replaceAll('\r', ' ');
        final script =
            '''
Add-Type -AssemblyName System.Speech
\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$s.SetOutputToWaveFile('${wav.path.replaceAll("'", "''")}')
\$s.Speak('$escaped')
\$s.Dispose()
''';
        await Process.run(
          'powershell',
          ['-NoProfile', '-NonInteractive', '-Command', script],
          runInShell: false,
        );
      }
      if (!await wav.exists() || await wav.length() < 128) {
        throw const FormatException('系统语音合成失败，没有可播放的音频');
      }
      return wav;
    } finally {
      if (await raw.exists()) {
        try {
          await raw.delete();
        } catch (_) {
          // A leftover temp file is not worth failing the utterance over.
        }
      }
    }
  }

  String _espeakVoice(String? hint) {
    final tag = (hint ?? '').toLowerCase();
    if (tag.startsWith('zh')) return 'cmn';
    if (tag.startsWith('ja')) return 'ja';
    if (tag.startsWith('en')) return 'en-us';
    return 'cmn';
  }
}
