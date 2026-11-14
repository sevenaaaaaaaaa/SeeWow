import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../domain/media_item.dart';
import '../watch_ai/watch_ai_client.dart';
import '../watch_ai/watch_ai_settings.dart';
import 'commentary_export.dart';
import 'commentary_script.dart';
import 'speech_synthesizer.dart';

/// How much of the film the commentary covers.
enum CommentaryMode {
  /// A 30-second opening hook: what the film is, why it is worth watching.
  intro,

  /// Remarks spread across the whole running time.
  full,
}

/// Generates a commentary script and speaks it over the film.
///
/// Two rules keep this honest: nothing is sent anywhere until the user asks,
/// and the original audio is ducked (never muted), so a failed remark is an
/// annoyance instead of a broken film.
class CommentaryController extends ChangeNotifier {
  CommentaryController({
    required this.video,
    required this.source,
    required this.client,
    required this.synthesizer,
    required this.outputDirectory,
    this.config,
  });

  final Player video;
  final MediaItem source;
  final WatchAiClient client;
  final SpeechSynthesizer synthesizer;
  final Directory outputDirectory;
  WatchAiConfig? config;

  final List<CommentarySegment> segments = [];
  bool generating = false;
  bool speaking = false;
  bool preparing = false;
  String? error;
  String script = '';
  CommentaryMode mode = CommentaryMode.full;

  Player? _audio;
  StreamSubscription<Duration>? _posSub;
  final Set<int> _spoken = {};
  double _lastVolume = 1;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Asks the configured model for a script. Returns the number of segments.
  Future<int> generate({
    required WatchAiConfig config,
    required double durationSeconds,
    String style = '影评人',
    int segmentCount = 8,
    CommentaryMode mode = CommentaryMode.full,
  }) async {
    final cfg = config;
    if (!cfg.enabled || !cfg.configured) {
      throw StateError('AI 陪看/解说尚未开启或配置');
    }
    if (!source.aiAllowed) throw const FormatException('此来源不允许 AI 处理');
    if (durationSeconds <= 0) throw const FormatException('影片时长未知，无法安排解说时间点');
    // An intro hook is three or four lines in the first half minute; asking for
    // eight of them would only produce remarks the parser drops.
    final count = mode == CommentaryMode.intro
        ? segmentCount.clamp(3, 4)
        : segmentCount.clamp(3, 12);
    generating = true;
    error = null;
    notifyListeners();
    try {
      final system = mode == CommentaryMode.intro
          ? '你是一位电影解说撰稿人。只输出 JSON 数组，不要任何解释或 Markdown。'
                '这次只写片头钩子：三到四句，总共能在 30 秒内说完，交代作品气质与看点，不剧透。'
          : '你是一位电影解说撰稿人。只输出 JSON 数组，不要任何解释或 Markdown。'
                '每段解说 40 到 90 个字，口语化、有信息量，不剧透结局。';
      final prompt = mode == CommentaryMode.intro
          ? '影片：《${source.showTitle ?? source.title}》'
                '${source.year == null ? '' : '（${source.year}）'}。'
                '类型：${source.genres.isEmpty ? '未知' : source.genres.join('、')}。'
                '简介：${source.overview.isEmpty ? '无' : source.overview}。'
                '请写 $count 段片头解说，全部落在前 30 秒内（第一段在 1 到 3 秒）。'
                '风格：$style。'
                '输出格式：[{"at": 秒数, "text": "解说词"}]，at 必须是递增的数字。'
          : '影片：《${source.showTitle ?? source.title}》'
                '${source.year == null ? '' : '（${source.year}）'}。'
                '类型：${source.genres.isEmpty ? '未知' : source.genres.join('、')}。'
                '简介：${source.overview.isEmpty ? '无' : source.overview}。'
                '片长约 ${(durationSeconds / 60).round()} 分钟。'
                '请写 $count 段解说，均匀分布在全片（第一段在 30 秒左右，最后一段在结束前 2 分钟）。'
                '风格：$style。'
                '输出格式：[{"at": 秒数, "text": "解说词"}]，at 必须是递增的数字。';
      final raw = await client.complete(
        config: cfg,
        system: system,
        prompt: prompt,
      );
      final parsed = mode == CommentaryMode.intro
          ? parseCommentaryScript(
              raw,
              duration: durationSeconds < 45 ? durationSeconds : 45,
              minimumGap: 3,
            )
          : parseCommentaryScript(raw, duration: durationSeconds);
      if (parsed.isEmpty) {
        throw const FormatException('模型没有返回可用的解说脚本，请重试');
      }
      this.config = cfg;
      this.mode = mode;
      script = raw;
      segments
        ..clear()
        ..addAll(parsed);
      _spoken.clear();
      notifyListeners();
      return parsed.length;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  /// Starts speaking the script as the film plays.
  Future<void> start() async {
    if (segments.isEmpty) throw const FormatException('请先生成解说脚本');
    if (await synthesizer.backend() == null) {
      throw const FormatException('这台设备没有可用的系统语音引擎');
    }
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }
    speaking = true;
    error = null;
    _spoken.clear();
    _lastVolume = video.state.volume;
    _audio ??= Player();
    _posSub?.cancel();
    _posSub = video.stream.position.listen((position) {
      _tick(position.inMilliseconds / 1000);
    });
    notifyListeners();
  }

  /// Synthesises every remark that has no audio yet, then writes one track.
  ///
  /// The export is the same audio the player would speak, laid on a silent
  /// timeline, so a user can keep it or hand it to another tool.
  Future<CommentaryExportResult> exportTrack() async {
    if (segments.isEmpty) throw const FormatException('请先生成解说脚本');
    if (await synthesizer.backend() == null) {
      throw const FormatException('这台设备没有可用的系统语音引擎');
    }
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.file != null) continue;
      final file = await synthesizer.synthesize(
        segment.text,
        directory: outputDirectory,
        languageHint: 'zh',
      );
      if (file == null) {
        throw FormatException('第 ${i + 1} 段解说没有合成出音频');
      }
      segments[i] = segment.withFile(file);
    }
    notifyListeners();
    return exportCommentaryTrack(segments: List.of(segments), directory: outputDirectory);
  }

  Future<void> _tick(double position) async {
    if (!speaking || preparing || _disposed) return;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.at > position + 1.5) break;
      if (_spoken.contains(i)) continue;
      // A remark more than 6 s behind the playhead is stale; drop it rather
      // than speak it out of context.
      _spoken.add(i);
      if (position - segment.at > 6) continue;
      await _speak(i, segment);
      return;
    }
  }

  Future<void> _speak(int index, CommentarySegment segment) async {
    final audio = _audio;
    if (audio == null) return;
    preparing = true;
    notifyListeners();
    try {
      final file = segment.file ?? await synthesizer.synthesize(
        segment.text,
        directory: outputDirectory,
        languageHint: 'zh',
      );
      if (file == null) throw const FormatException('系统语音不可用');
      segments[index] = segment.withFile(file);
      await audio.setVolume(0);
      await audio.open(Media(file.uri.toString()));
      // Duck the film instead of muting it: a broken remark must never leave
      // the viewer in silence.
      await video.setVolume(_lastVolume * 0.35);
      await audio.play();
      final seconds = await wavDurationSeconds(file);
      await Future<void>.delayed(
        Duration(milliseconds: ((seconds <= 0 ? 3 : seconds) * 1000).round() + 120),
      );
    } catch (e) {
      error = '解说播放失败：$e';
    } finally {
      await video.setVolume(_lastVolume);
      preparing = false;
      notifyListeners();
    }
  }

  Future<void> stop({bool resumeVolume = true}) async {
    speaking = false;
    _posSub?.cancel();
    _posSub = null;
    try {
      await _audio?.stop();
    } catch (_) {}
    if (resumeVolume) {
      try {
        await video.setVolume(_lastVolume);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> close() async {
    _disposed = true;
    await stop();
    await _audio?.dispose();
    _audio = null;
    super.dispose();
  }
}
