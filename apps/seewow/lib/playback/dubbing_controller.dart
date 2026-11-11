import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../domain/media_item.dart';
import '../metadata/metadata_transport.dart';
import 'audio_capture.dart';
import 'voice_translation.dart';

class _DubChunk {
  _DubChunk(this.at, this.duration, this.speech);
  final double at, duration;
  final TranslatedSpeech speech;
}

/// Two bounded chunks, one API request, foreground VOD only. Never edits the media.
class DubbingController extends ChangeNotifier {
  DubbingController({
    required this.video,
    required this.source,
    required this.client,
    this.audioOutput,
    this.effectiveVolume,
  });
  final Player video;
  final MediaItem source;
  final VoiceTranslationClient client;
  final Player? audioOutput;
  final double Function()? effectiveVolume;
  final AudioCapture _capture = AudioCapture();
  Player? _audio;
  bool active = false, preparing = false, paused = false, _disposed = false;
  String? error;
  String text = '';
  WavAudio? _currentAudio;
  double? get level => !active || preparing || _currentAudio == null
      ? null
      : paused || _audio?.state.playing != true
      ? 0
      : _currentAudio!.levelAt(
          _audio!.state.position.inMilliseconds / 1000,
          volume: _audio!.state.volume,
        );
  int _revision = 0;
  Completer<void>? _pauseGate;
  Future<void>? _runFuture;
  Completer<void> _stopSignal = Completer<void>();
  Completer<void>? _chunkDone;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _mute(bool value) async {
    final native = video.platform;
    if (native is NativePlayer && !native.disposed)
      await native.setProperty('mute', value ? 'yes' : 'no');
  }

  Future<void> start() async {
    if (active) return;
    await _runFuture;
    if (!source.aiAllowed) throw const FormatException('此来源不允许 AI 处理');
    client.config.validate();
    if (video.state.duration.inMilliseconds <= 0)
      throw const FormatException('译配需要可定位的点播影片');
    final revision = ++_revision;
    active = true;
    paused = false;
    preparing = true;
    error = null;
    _stopSignal = Completer<void>();
    await video.pause();
    await video.setRate(1);
    notifyListeners();
    _runFuture = _run(revision);
  }

  Future<_DubChunk> _prepare(double at, double seconds, int revision) async {
    final sourceAudio = await _capture.capture(source, at, seconds);
    if (!active || revision != _revision) throw MetadataCancelled();
    final speech = await client.translate(source, sourceAudio, at);
    if (!active || revision != _revision) throw MetadataCancelled();
    return _DubChunk(at, sourceAudio.duration, speech);
  }

  Future<void> _run(int revision) async {
    Directory? dir;
    final audio =
        audioOutput ??
        Player(
          configuration: const PlayerConfiguration(
            title: 'SeeWow 译音',
            muted: true,
          ),
        );
    final completed = audio.stream.completed.listen((v) {
      if (v && _chunkDone != null && !_chunkDone!.isCompleted)
        _chunkDone!.complete();
    });
    final failed = audio.stream.error.listen((_) {
      if (_chunkDone != null && !_chunkDone!.isCompleted)
        _chunkDone!.completeError(const FormatException('译音无法播放'));
    });
    _audio = audio;
    var normalEnd = false;
    try {
      dir = await Directory.systemTemp.createTemp('seewow-voice-');
      final total = video.state.duration.inMilliseconds / 1000;
      var at = video.state.position.inMilliseconds / 1000, index = 0;
      Future<Object> prepare(double start) => _prepare(
        start,
        math.min(6, total - start),
        revision,
      ).then<Object>((c) => c, onError: (Object e) => e);
      Future<Object>? next = total - at >= .5 ? prepare(at) : null;
      while (active && revision == _revision && next != null) {
        preparing = true;
        notifyListeners();
        final result = await next;
        if (result is! _DubChunk) throw result;
        if (!active || revision != _revision) break;
        final chunk = result;
        final following = chunk.at + chunk.duration;
        next = total - following >= .5 ? prepare(following) : null;
        final file = File('${dir.path}/${index++}.wav');
        await file.writeAsBytes(chunk.speech.audio.bytes, flush: true);
        if (!active || revision != _revision) break;
        final chunkDone = Completer<void>();
        _chunkDone = chunkDone;
        final completion = Future.any<void>([
          chunkDone.future,
          _stopSignal.future,
        ]).then<Object?>((_) => null, onError: (Object e) => e);
        await audio.open(Media(file.path), play: false);
        await audio.setVolume(effectiveVolume?.call() ?? video.state.volume);
        await audio.setRate(chunk.speech.audio.duration / chunk.duration);
        await video.seek(Duration(milliseconds: (chunk.at * 1000).round()));
        await _mute(true);
        text = chunk.speech.text;
        _currentAudio = chunk.speech.audio;
        preparing = false;
        notifyListeners();
        if (paused) {
          _pauseGate ??= Completer<void>();
          await _pauseGate!.future;
        }
        if (!active || revision != _revision) break;
        await video.play();
        await audio.play();
        final failure = await completion;
        if (failure != null) throw failure;
        if (!active || revision != _revision) break;
        await video.pause();
        await audio.stop();
        if (await file.exists()) await file.delete();
        normalEnd = next == null;
      }
    } catch (e) {
      if (revision == _revision && e is! MetadataCancelled)
        error = e is FormatException ? '${e.message}' : '译配中断，已恢复原片声音';
    } finally {
      if (!_stopSignal.isCompleted) _stopSignal.complete();
      await completed.cancel();
      await failed.cancel();
      _chunkDone = null;
      await _capture.cancel();
      client.close();
      await audio.dispose();
      if (identical(_audio, audio)) _audio = null;
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
      if (revision == _revision) {
        active = false;
        preparing = false;
        text = '';
        await _mute(false);
        if (!paused && !normalEnd && !_disposed) await video.play();
        notifyListeners();
      }
    }
  }

  Future<void> togglePause() async {
    paused = !paused;
    if (paused) {
      await video.pause();
      await _audio?.pause();
    } else {
      final gate = _pauseGate;
      _pauseGate = null;
      if (gate != null && !gate.isCompleted) gate.complete();
      if (!preparing) {
        await video.play();
        await _audio?.play();
      }
    }
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    await _audio?.setVolume(effectiveVolume?.call() ?? value);
  }

  Future<void> stop({bool resumeOriginal = true}) async {
    _revision++;
    active = false;
    preparing = false;
    text = '';
    _currentAudio = null;
    if (!_stopSignal.isCompleted) _stopSignal.complete();
    client.close();
    final gate = _pauseGate;
    _pauseGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
    await _capture.cancel();
    await _audio?.stop();
    await _mute(false);
    if (resumeOriginal && !paused && !_disposed) await video.play();
    notifyListeners();
  }

  Future<void> close() async {
    _disposed = true;
    await stop(resumeOriginal: false);
    await _runFuture;
    super.dispose();
  }
}
