import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../features/watch_ai_view.dart';
import '../features/subtitle_dialog.dart';
import '../metadata/subtitles.dart';
import '../watch_ai/watch_ai_controller.dart';
import '../watch_ai/watch_frame.dart';
import '../features/frame_bookmarks_view.dart';
import '../features/playback_settings_view.dart';
import 'playback_preferences.dart';
import 'cinema_entrance.dart';
import 'playback_window.dart';
import 'frame_bookmarks.dart';
import 'audio_level.dart';
import 'audio_privacy.dart';
import 'playback_gestures.dart';
import 'sensitive_content.dart';
import 'voice_translation.dart';
import 'dubbing_controller.dart';
import '../features/voice_translation_view.dart';
import '../sources/native_bridge.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../design/pressable.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    this.startAt,
    this.isLive = false,
    this.onProgress,
    this.resolve,
  });
  final MediaItem item;
  final double? startAt;
  final bool isLive;
  final Future<MediaItem> Function(MediaItem)? resolve;
  final void Function(double position, double duration)? onProgress;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late final WatchAiController _watchAi;
  StreamSubscription<List<String>>? _subtitleSub;
  late final Player _player;
  late final VideoController _controller;
  late final AudioLevel _level;
  final PlaybackWindow _window = PlaybackWindow();
  final AbLoop _ab = AbLoop();
  final _prefs = PlaybackPreferences.I;
  final _privacy = AudioPrivacy(DailyVolumeMemory());
  Timer? _routePoll, _sensitiveTimer;
  String? _routeToken;
  SensitiveContentClient? _sensitiveClient;
  bool _scanningSensitive = false, _locked = false;
  double? _seekPreview;
  bool get _backgroundAllowed => _prefs.background || _locked;
  bool _introDone = false,
      _ready = false,
      _foreground = true,
      _pausedForBackground = false,
      _systemPip = false,
      _enteringPip = false,
      _savingFrame = false,
      _loopSeeking = false;
  double get _volume => _privacy.effectiveVolume;
  DubbingController? _voice;
  String? _voiceErrorShown;
  VideoTrack? _backgroundVideoTrack;
  bool get _playbackRunning =>
      _voice?.active == true ? !_voice!.paused : _playing;
  double? get _audioLevelValue =>
      _voice?.active == true ? _voice!.level : _level.level;
  final _focus = FocusNode();
  final _videoKey = GlobalKey<VideoState>();
  double _lastReported = 0;
  StreamSubscription<bool>? _bufferSub;
  StreamSubscription<String>? _errorSub;
  String? _error;
  MediaItem? _target;
  Timer? _hideTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playSub;

  double _position = 0;
  double _duration = 0;
  bool _playing = false;
  bool _controls = true;
  bool get _muted => _privacy.effectiveVolume == 0;
  bool _buffering = true;
  bool _hoverBar = false;
  bool _mobileFullscreen = false;
  bool _capturingAiFrame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchAi = WatchAiController(
      title: widget.item.displayTitle,
      contentAllowed: widget.item.aiAllowed,
    )..addListener(_aiChanged);
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'SeeWow',
        ready: null,
        muted: true,
      ),
    );
    _controller = VideoController(_player);
    _level = AudioLevel(_player)..addListener(_aiChanged);
    _window.addListener(_aiChanged);
    _introDone = widget.isLive || widget.item.kind == MediaKind.audio;
    _prefs.addListener(_playbackPreferencesChanged);
    PlaybackWindow.channel.setMethodCallHandler(_platformEvent);
    _subtitleSub = _player.stream.subtitle.listen(
      (lines) => _watchAi.setSubtitle(
        lines.where((s) => s.trim().isNotEmpty).toSet().join('\n'),
      ),
    );
    _posSub = _player.stream.position.listen((p) {
      _watchAi.setPosition(p.inMilliseconds / 1000);
      if (mounted) setState(() => _position = p.inMilliseconds / 1000);
      if (_ab.enabled && _playing && !_loopSeeking && _position >= _ab.b!) {
        _loopSeeking = true;
        _player
            .seek(Duration(milliseconds: (_ab.a! * 1000).round()))
            .whenComplete(() => _loopSeeking = false);
      }
      if ((_position - _lastReported).abs() >= 5 && _duration > 0) {
        _lastReported = _position;
        widget.onProgress?.call(_position, _duration);
        _updateNativePlayback();
      }
    });
    _durSub = _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d.inMilliseconds / 1000);
    });
    _playSub = _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
      _updateNativePlayback();
    });
    _bufferSub = _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    _errorSub = _player.stream.error.listen((e) {
      if (mounted)
        setState(() {
          _error = '播放失败，请检查片源连接或文件是否可读';
          _buffering = false;
        });
    });
    _open().catchError((Object e) {
      if (mounted)
        setState(() {
          _error = '无法打开媒体，请检查来源连接后重试';
          _buffering = false;
        });
    });
    _scheduleHide();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _focus.requestFocus();
      try {
        if (PlaybackWindow.desktop)
          await _window.begin(
            enterFullscreen:
                _prefs.fullscreen &&
                !widget.isLive &&
                widget.item.kind != MediaKind.audio,
          );
        else if (_prefs.fullscreen &&
            !widget.isLive &&
            widget.item.kind != MediaKind.audio)
          await _toggleFullscreen();
        await _configureBackground();
      } catch (_) {
        if (mounted) _message('系统窗口或后台能力暂不可用，仍可在当前窗口播放');
      }
    });
  }

  void _aiChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasRunning = _playbackRunning;
    _foreground = state == AppLifecycleState.resumed;
    _level.visible = _foreground && _controls && _voice?.active != true;
    if (state == AppLifecycleState.resumed) {
      if (_backgroundVideoTrack != null) {
        final track = _backgroundVideoTrack!;
        _backgroundVideoTrack = null;
        _player.setVideoTrack(track);
      }
      _watchAi.suspend(false);
      if (_pausedForBackground) {
        _pausedForBackground = false;
        _player.play();
      }
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _watchAi.suspend(true);
      if (Platform.isIOS &&
          _backgroundAllowed &&
          !_systemPip &&
          !_enteringPip &&
          widget.item.kind != MediaKind.audio) {
        _backgroundVideoTrack ??= _player.state.track.video;
        _player.setVideoTrack(VideoTrack.no());
      }
      if (_voice?.active == true)
        _stopDubbing(resumeOriginal: _backgroundAllowed || _systemPip);
      if (!_backgroundAllowed && !_systemPip && !_enteringPip) {
        _pausedForBackground = wasRunning;
        _player.pause();
      }
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _configureBackground() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    await PlaybackWindow.channel.invokeMethod('background', {
      'enabled': _backgroundAllowed,
      'title': widget.item.displayTitle,
    });
    _updateNativePlayback();
  }

  void _playbackPreferencesChanged() {
    _scanUnavailable = false;
    _configureSensitiveScan();
    _level.enable(_prefs.meter);
    _configureBackground().catchError((Object _) {
      _message('后台播放设置未能应用，请检查系统支持');
    });
    if (mounted) setState(() {});
  }

  void _updateNativePlayback() {
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    PlaybackWindow.channel
        .invokeMethod('update', {
          'title': widget.item.displayTitle,
          'playing': _playing,
          'position': (_position * 1000).round(),
          'duration': (_duration * 1000).round(),
        })
        .catchError((Object _) => null);
  }

  Future<void> _platformEvent(MethodCall call) async {
    if (!mounted) return;
    final args = call.arguments is Map ? call.arguments as Map : const {};
    if (call.method == 'audio.routeChanged') {
      _acceptAudioRoute(args);
      return;
    }
    if (call.method == 'pip.mode') {
      setState(() => _systemPip = args['active'] == true);
    }
    if (call.method == 'pip.restore') {
      setState(() => _systemPip = false);
      if (args['position'] is num)
        await _player.seek(
          Duration(milliseconds: (args['position'] as num).round()),
        );
      if (args['playing'] == true && (_foreground || _backgroundAllowed))
        await _player.play();
    }
    if (call.method == 'action') {
      switch (args['action']) {
        case 'play':
          if (_voice?.active == true) {
            if (_voice!.paused) await _voice!.togglePause();
          } else {
            await _player.play();
          }
        case 'pause':
          if (_voice?.active == true) {
            if (!_voice!.paused) await _voice!.togglePause();
          } else {
            await _player.pause();
          }
        case 'toggle':
          _togglePlay();
        case 'stop':
          if (_locked) {
            _toggleScreenLock();
            await WidgetsBinding.instance.endOfFrame;
          }
          if (mounted) Navigator.of(context).maybePop();
        case 'seek':
          if (args['position'] is num) {
            await _seekTo((args['position'] as num).toDouble() / 1000);
          }
      }
    }
  }

  Future<void> _miniPlayer() async {
    try {
      if (_voice?.active == true) await _stopDubbing();
      if (PlaybackWindow.desktop) {
        await _window.toggleMini();
        if (mounted) setState(() {});
      } else {
        _enteringPip = true;
        final target = _target ?? widget.item;
        final resume = _player.state.playing;
        if (Platform.isIOS) await _player.pause();
        try {
          final ok = await PlaybackWindow.channel.invokeMethod<bool>('pip', {
            'url': target.locator,
            'headers': target.httpHeaders,
            'position': (_position * 1000).round(),
            'playing': resume,
            'volume': _privacy.effectiveVolume / 100,
            'routeToken': _routeToken,
            'sensitive': _privacy.sensitive,
          });
          if (ok != true) throw const FormatException('此设备或当前媒体格式不支持系统画中画');
          if (mounted) setState(() => _systemPip = true);
        } catch (_) {
          if (resume && Platform.isIOS) await _player.play();
          rethrow;
        } finally {
          _enteringPip = false;
        }
      }
    } catch (e) {
      _message(
        e is PlatformException
            ? (e.message ?? '系统小窗不可用')
            : e is FormatException
            ? '${e.message}'
            : '系统小窗不可用',
      );
    }
    if (mounted) _reveal();
  }

  void _finishEntrance() {
    if (!mounted || _introDone) return;
    setState(() => _introDone = true);
    if (_ready && (_foreground || _backgroundAllowed)) _player.play();
  }

  Future<void> _markLoop() async {
    if (widget.isLive || _duration <= 0) {
      _message('直播或不可定位的媒体不支持 AB 循环');
      return;
    }
    try {
      if (_voice?.active == true) await _stopDubbing();
      final text = _ab.mark(_position);
      setState(() {});
      _message(
        '$text${_ab.enabled ? ' · ${playbackTime(_ab.a!)}—${playbackTime(_ab.b!)}' : ''}',
      );
    } catch (e) {
      _message(e is FormatException ? '${e.message}' : '循环点设置失败');
    }
    _reveal();
  }

  Future<void> _saveFrame() async {
    if (_savingFrame || widget.item.kind == MediaKind.audio || !_ready) return;
    _savingFrame = true;
    final voice = _voice?.active == true ? _voice : null;
    final resume = voice != null ? !voice.paused : _playing;
    _hoverBar = true;
    _hideTimer?.cancel();
    final note = TextEditingController();
    try {
      if (voice != null && !voice.paused) await voice.togglePause();
      await _player.pause();
      final at = _player.state.position.inMilliseconds / 1000;
      final image = await _player.screenshot(format: 'image/jpeg');
      if (!mounted) return;
      if (image == null) throw const FormatException('当前画面无法截取，请等待画面加载');
      await FrameBookmarks.validateImage(image);
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('收藏 ${playbackTime(at)} 的画面'),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 240,
                    child: Image.memory(image, fit: BoxFit.contain),
                  ),
                  TextField(
                    controller: note,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '备注（可选）'),
                  ),
                  const Text('仅保存在本机，不发送给 AI 服务，不修改影片。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('收藏精彩帧'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await FrameBookmarks.I.add(widget.item, at, image, note: note.text);
        _message('精彩帧已收藏至本机');
      }
    } catch (e) {
      _message(e is FormatException ? '${e.message}' : '画面收藏失败，请检查本机存储');
    } finally {
      note.dispose();
      _savingFrame = false;
      _hoverBar = false;
      if (mounted) {
        if (resume && _foreground) {
          if (voice?.active == true && voice!.paused)
            await voice.togglePause();
          else
            await _player.play();
        }
        _reveal();
      }
    }
  }

  Future<void> _showFrames() async {
    await showFrameBookmarks(
      context,
      itemId: widget.item.id,
      onSelect: widget.isLive
          ? null
          : (frame) {
              _seekTo(frame.seconds);
            },
    );
    if (mounted) _reveal();
  }

  Future<void> _applyAudioPrivacy() async {
    // Queue native player mutations so a late slider update cannot overtake mute.
    _audioWrites = _audioWrites.catchError((Object _) {}).then((_) async {
      if (!mounted) return;
      final gain = _privacy.effectiveVolume;
      try {
        await PlaybackWindow.channel.invokeMethod('audio.volume', {
          'volume': gain / 100,
          'routeToken': _routeToken,
          'sensitive': _privacy.sensitive,
        });
      } catch (_) {}
      if (!mounted) return;
      await _player.setVolume(_privacy.effectiveVolume);
      if (_voice?.active == true)
        await _voice?.setVolume(_privacy.effectiveVolume);
    });
    if (mounted) setState(() {});
    await _audioWrites;
  }

  Future<void> _audioWrites = Future.value();

  Future<void> _changeVolume(double value) async {
    _privacy.selectVolume(value);
    await _applyAudioPrivacy();
    await _privacy.persist();
    if (_privacy.blocked) _message('本片已标记敏感内容，外放保持静音；请使用已确认的耳机');
  }

  void _toggleMute() {
    if (_muted) {
      _unmute();
    } else {
      _privacy.muted = true;
      _applyAudioPrivacy();
    }
  }

  void _unmute() {
    if (!_muted) return;
    if (!_privacy.unmute()) _message('敏感内容外放保护中，无法解除静音');
    _applyAudioPrivacy();
    _reveal();
  }

  Future<void> _readAudioRoute({bool event = false}) async {
    try {
      final result = await PlaybackWindow.channel
          .invokeMapMethod<String, dynamic>('audio.route');
      if (!mounted || result == null) return;
      _acceptAudioRoute(result, event: event);
    } catch (_) {
      /* Unavailable platforms retain the conservative unknown route. */
    }
  }

  void _acceptAudioRoute(Map args, {bool event = true}) {
    final token = '${args['token'] ?? args['route']}';
    if (!event && token == _routeToken) return;
    _routeToken = token;
    _privacy.changeRoute(switch (args['route']) {
      'headphones' => AudioOutputRoute.headphones,
      'speaker' => AudioOutputRoute.speaker,
      _ => AudioOutputRoute.unknown,
    });
    _applyAudioPrivacy();
    if (event) _message('音频输出已变化，已静音；双击画面按新输出音量恢复');
  }

  void _detectSensitive() {
    if (_privacy.sensitive) return;
    _privacy.detectSensitive();
    _sensitiveTimer?.cancel();
    _applyAudioPrivacy();
    _message(_privacy.blocked ? '本片已识别或标记为敏感内容，外放保持静音' : '本片已标记敏感内容，切换外放时保持静音');
  }

  void _configureSensitiveScan() {
    _sensitiveTimer?.cancel();
    _sensitiveClient?.close();
    _sensitiveClient = null;
    if (_privacy.sensitive ||
        !widget.item.aiAllowed ||
        !(_target ?? widget.item).aiAllowed ||
        widget.item.kind == MediaKind.audio ||
        !_prefs.sensitiveScan ||
        _prefs.sensitiveEndpoint.isEmpty)
      return;
    _sensitiveClient = SensitiveContentClient(_prefs.sensitiveEndpoint);
    _sensitiveTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _scanSensitive(),
    );
  }

  Future<void> _scanSensitive() async {
    final client = _sensitiveClient;
    if (client == null ||
        _scanningSensitive ||
        _privacy.sensitive ||
        !_ready ||
        !_foreground ||
        !_playing ||
        _systemPip ||
        !_introDone ||
        _capturingAiFrame)
      return;
    _scanningSensitive = true;
    try {
      final bytes = await reduceWatchFrame(
        await _player.screenshot(format: 'image/jpeg'),
      );
      if (bytes != null &&
          await client.detect(bytes) &&
          mounted &&
          identical(client, _sensitiveClient)) {
        _detectSensitive();
      }
    } catch (_) {
      if (mounted && identical(client, _sensitiveClient)) {
        _sensitiveTimer?.cancel();
        setState(() => _scanUnavailable = true);
        _message('本机敏感画面检测不可用，仍按内容标记保护；可在播放设置重试');
      }
    } finally {
      _scanningSensitive = false;
    }
  }

  bool _scanUnavailable = false;
  void _toggleScreenLock() {
    setState(() {
      _locked = !_locked;
      _controls = !_locked;
      _seekPreview = null;
    });
    _hideTimer?.cancel();
    _level.visible = !_locked && _foreground && _voice?.active != true;
    _configureBackground().catchError((Object _) {
      _message('系统未允许后台播放，请保持应用在前台');
    });
    if (!_locked) _reveal();
    _message(_locked ? '触控已锁定，继续播放；双指长按或长按锁按钮解锁' : '触控已解锁');
  }

  void _voiceChanged() {
    if (!mounted) return;
    final voice = _voice;
    if (voice?.active != true) {
      _level.visible = _foreground && _controls;
      _watchAi.suspend(!_foreground);
      if (voice?.error != null && _voiceErrorShown != voice!.error) {
        _voiceErrorShown = voice.error;
        _message('${voice.error} · 已恢复原片声音');
      }
    }
    setState(() {});
  }

  Future<void> _stopDubbing({bool resumeOriginal = true}) async {
    await _voice?.stop(resumeOriginal: resumeOriginal);
    _watchAi.suspend(!_foreground);
    _level.visible = _foreground && _controls;
    if (mounted) setState(() {});
  }

  Future<void> _startDubbing() async {
    if (widget.isLive || !widget.item.aiAllowed || !_ready || !_foreground) {
      _message('译配仅用于允许 AI 的前台点播影片');
      return;
    }
    try {
      final config = await VoiceTranslationConfig.load();
      config.validate();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('开启缓冲语音译配？'),
          content: SingleChildScrollView(
            child: Text(
              '目标语言：${config.language}\n服务：${Uri.parse(config.endpoint).host}\n\n将连续发送每段约 6 秒的原片音频，以 1× 速度生成译音。服务声明保留音色，但可能改变声音细节，缓冲不及时会暂停等候。\n\n不发送播放地址、文件路径或片源凭据。确认你有权使用并向此服务发送音频，且已确认服务的音色使用许可与费用。跳播、后台或小窗会停止译配并恢复原声。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认并开启译配'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !_foreground) return;
      final old = _voice;
      if (old != null) {
        old.removeListener(_voiceChanged);
        await old.close();
      }
      final token = await NativeBridge.secretRead(config.secretKey) ?? '';
      if (!mounted || !_foreground) return;
      _ab.clear();
      final voice = DubbingController(
        video: _player,
        source: _target ?? widget.item,
        effectiveVolume: () => _privacy.effectiveVolume,
        client: VoiceTranslationClient(config, token: token),
      );
      _voice = voice;
      _voiceErrorShown = null;
      voice.addListener(_voiceChanged);
      _level.visible = false;
      _watchAi.suspend(true);
      await voice.start();
      if (mounted) setState(() {});
    } catch (e) {
      _message(
        e is FormatException
            ? '${e.message}；可在播放工具中配置语音服务'
            : '语音译配未能开启，请检查服务配置',
      );
    }
  }

  Future<void> _seekTo(double seconds) async {
    if (widget.isLive) return;
    final resume = _voice?.active == true && _voice?.paused == false;
    if (_voice?.active == true) await _stopDubbing(resumeOriginal: false);
    _ab.clear();
    await _player.seek(
      Duration(milliseconds: (seconds.clamp(0, _duration) * 1000).round()),
    );
    if (resume) await _player.play();
    if (mounted) _reveal();
  }

  Future<Uint8List?> _captureAiFrame() async {
    if (_capturingAiFrame) throw const FormatException('上一张画面仍在处理，请稍后再试');
    _capturingAiFrame = true;
    try {
      final raw = await _player.screenshot(format: 'image/jpeg');
      if (!mounted || !_watchAi.active) return null;
      return await reduceWatchFrame(raw);
    } finally {
      _capturingAiFrame = false;
    }
  }

  Future<void> _showCompanion() async {
    if (_voice?.active == true) await _stopDubbing();
    final resume = _playing;
    await _player.pause();
    if (!mounted) return;
    _hideTimer?.cancel();
    _hoverBar = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 720),
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .86,
          child: WatchCompanionPanel(
            controller: _watchAi,
            capture: _captureAiFrame,
            onImportSubtitle: _importSubtitle,
            onSelectSubtitle: _selectSubtitle,
          ),
        ),
      );
    } finally {
      _watchAi.stop();
      _hoverBar = false;
      if (mounted) {
        if (resume) await _player.play();
        _reveal();
      }
    }
  }

  Future<void> _importSubtitle() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: SubtitleFiles.extensions,
      );
      if (file == null || !mounted) return;
      if ((await file.length() ?? 67108865) > 64 * 1024 * 1024)
        throw const FormatException('字幕文件不能超过 64 MiB');
      if (file.path != null) {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(File(file.path!).uri.toString(), title: file.name),
        );
      } else {
        final text = utf8
            .decode(await file.readAsBytes())
            .replaceFirst('\uFEFF', '');
        await _player.setSubtitleTrack(
          SubtitleTrack.data(text, title: file.name),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException ? e.message : '字幕导入失败，请检查格式、编码和文件访问权限',
            ),
          ),
        );
    }
  }

  Future<void> _nearbySubtitles() async {
    try {
      final files = [
        ...await SubtitleCache().list(widget.item),
        ...await SubtitleFiles.discover(
          _target?.locator ?? widget.item.locator,
        ),
      ];
      if (!mounted) return;
      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未发现同名本机旁车字幕，可选择内嵌轨道、导入文件或搜索在线字幕')),
        );
        return;
      }
      final selected = await showDialog<LocalSubtitle>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('缓存与同目录字幕'),
          children: [
            for (final file in files)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, file),
                child: Text(file.name),
              ),
          ],
        ),
      );
      if (selected != null && mounted)
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(
            File(selected.path).uri.toString(),
            title: selected.name,
          ),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法读取同目录字幕，请检查目录权限')));
    }
  }

  Future<void> _findSubtitle() async {
    final result = await findSubtitle(context, widget.item);
    if (result == null || !mounted) return;
    try {
      final saved = await SubtitleCache().save(
        widget.item,
        result.text,
        language: result.language,
      );
      if (mounted)
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(
            File(saved.path).uri.toString(),
            title: result.title,
            language: result.language,
          ),
        );
    } catch (_) {
      if (mounted)
        await _player.setSubtitleTrack(
          SubtitleTrack.data(
            result.text,
            title: result.title,
            language: result.language,
          ),
        );
    }
  }

  Future<void> _selectSubtitle() async {
    final tracks = _player.state.tracks.subtitle;
    final track = await showDialog<SubtitleTrack>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择字幕轨道'),
        children: [
          for (final t in tracks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
              child: Text(
                t.id == 'no'
                    ? '关闭原字幕'
                    : t.id == 'auto'
                    ? '自动选择'
                    : '${t.title ?? '字幕轨道 ${t.id}'}${t.language == null ? '' : ' · ${t.language}'}',
              ),
            ),
        ],
      ),
    );
    if (track != null && mounted) await _player.setSubtitleTrack(track);
  }

  Future<void> _open() async {
    final target = await widget.resolve?.call(widget.item) ?? widget.item;
    if (!mounted) return;
    _target = target;
    _level.source = target;
    await _privacy.load();
    if (!mounted) return;
    if (hasSensitiveMetadata(target.metadata) ||
        hasSensitiveMetadata(widget.item.metadata))
      _privacy.detectSensitive();
    await _readAudioRoute();
    if (!mounted) return;
    _routePoll = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _readAudioRoute(),
    );
    await _applyAudioPrivacy();
    // PlayerConfiguration.muted closes the startup window; gain zero now keeps
    // silence even when the dubbing engine releases its own native mute flag.
    if (_player.platform is NativePlayer) {
      await (_player.platform as NativePlayer).setProperty('mute', 'no');
    }
    if (!mounted) return;
    await _player.open(
      Media(
        target.locator,
        httpHeaders: target.httpHeaders.isEmpty ? null : target.httpHeaders,
      ),
      play: false,
    );
    if (widget.isLive) {
      await _applyAudioPrivacy();
      _ready = true;
      _configureSensitiveScan();
      await _player.play();
      return;
    }
    final start = widget.startAt ?? widget.item.position;
    if (start > 5)
      await _player.seek(Duration(milliseconds: (start * 1000).round()));
    await _applyAudioPrivacy();
    _ready = true;
    _configureSensitiveScan();
    await _level.enable(_prefs.meter);
    if (_introDone && (_foreground || _backgroundAllowed)) await _player.play();
  }

  void _scheduleHide() {
    if (Platform.environment['SEEWOW_KEEP_CONTROLS'] == '1') return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_hoverBar && _introDone && _playbackRunning) {
        setState(() => _controls = false);
        _level.visible = false;
      }
    });
  }

  void _reveal() {
    if (_locked || !mounted) return;
    setState(() => _controls = true);
    _level.visible = _foreground && _voice?.active != true;
    _scheduleHide();
  }

  void _togglePlay() {
    if (_systemPip && Platform.isIOS) {
      PlaybackWindow.channel.invokeMethod('pip.stop');
      return;
    }
    if (!_introDone) {
      _finishEntrance();
      return;
    }
    if (_voice?.active == true)
      _voice!.togglePause();
    else
      _player.playOrPause();
    _reveal();
  }

  void _seekBy(double seconds) {
    if (widget.isLive) return;
    final target = (_position + seconds).clamp(0, _duration);
    _seekTo(target.toDouble());
    _reveal();
  }

  Future<void> _toggleFullscreen() async {
    if (PlaybackWindow.desktop) {
      try {
        await _window.toggleFullscreen();
        if (mounted) setState(() {});
      } catch (_) {
        _message('系统全屏暂不可用');
      }
      return;
    }
    // Keep our controls on the current route when rotating the mobile player.
    setState(() => _mobileFullscreen = !_mobileFullscreen);
    await SystemChrome.setEnabledSystemUIMode(
      _mobileFullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.manual,
      overlays: _mobileFullscreen ? [] : SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(
      _mobileFullscreen
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [],
    );
    if (mounted) _reveal();
  }

  @override
  void dispose() {
    if (_mobileFullscreen) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        ),
      );
      unawaited(SystemChrome.setPreferredOrientations([]));
    }
    WidgetsBinding.instance.removeObserver(this);
    _prefs.removeListener(_playbackPreferencesChanged);
    _level.dispose();
    _window.removeListener(_aiChanged);
    _voice?.removeListener(_voiceChanged);
    _voice?.close();
    _routePoll?.cancel();
    _sensitiveTimer?.cancel();
    _sensitiveClient?.close();
    PlaybackWindow.channel.setMethodCallHandler(null);
    _window.close().catchError((Object _) {});
    if (Platform.isIOS || Platform.isAndroid)
      PlaybackWindow.channel.invokeMethod('end').catchError((Object _) => null);
    _subtitleSub?.cancel();
    _watchAi.dispose();
    _hideTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _bufferSub?.cancel();
    _errorSub?.cancel();
    if (_duration > 0) widget.onProgress?.call(_position, _duration);
    _player.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_locked,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _locked) _message('触控已锁定，请先长按解锁');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.keyL ||
                (_locked && event.logicalKey == LogicalKeyboardKey.escape)) {
              _toggleScreenLock();
              return KeyEventResult.handled;
            }
            if (_locked) return KeyEventResult.handled;
            switch (event.logicalKey) {
              case LogicalKeyboardKey.space:
                _togglePlay();
                return KeyEventResult.handled;
              case LogicalKeyboardKey.arrowLeft:
                _seekBy(-10);
                return KeyEventResult.handled;
              case LogicalKeyboardKey.arrowRight:
                _seekBy(30);
                return KeyEventResult.handled;
              case LogicalKeyboardKey.arrowUp:
                _changeVolume(_volume + 5);
                _reveal();
                return KeyEventResult.handled;
              case LogicalKeyboardKey.arrowDown:
                _changeVolume(_volume - 5);
                _reveal();
                return KeyEventResult.handled;
              case LogicalKeyboardKey.keyM:
                _toggleMute();
                _reveal();
                return KeyEventResult.handled;
              case LogicalKeyboardKey.escape:
                if (_window.mini) {
                  _miniPlayer();
                } else if (_window.fullscreen || _mobileFullscreen) {
                  _toggleFullscreen();
                } else {
                  Navigator.of(context).maybePop();
                }
                return KeyEventResult.handled;
              case LogicalKeyboardKey.keyB:
                _markLoop();
                return KeyEventResult.handled;
              case LogicalKeyboardKey.keyS:
                _saveFrame();
                return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: _controls
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            onHover: (_) {
              if (!_controls && !_locked) _reveal();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                PlaybackGestures(
                  locked: _locked,
                  position: _position,
                  duration: _duration,
                  seekEnabled: !widget.isLive && _introDone && _ready,
                  onSeek: _seekTo,
                  onPreview: (v) {
                    if (mounted) setState(() => _seekPreview = v);
                  },
                  onToggleLock: _toggleScreenLock,
                  onUnmute: _unmute,
                  onTap: () {
                    if (_locked) return;
                    if (_controls) {
                      setState(() => _controls = false);
                      _hideTimer?.cancel();
                    } else {
                      _reveal();
                    }
                  },
                  child: Video(
                    key: _videoKey,
                    controller: _controller,
                    controls: NoVideoControls,
                    pauseUponEnteringBackgroundMode: false,
                    resumeUponEnteringForegroundMode: false,
                    subtitleViewConfiguration: SubtitleViewConfiguration(
                      visible:
                          !(_watchAi.active &&
                              _watchAi.config.subtitles &&
                              _watchAi.currentText.isNotEmpty),
                    ),
                    fill: Colors.black,
                  ),
                ),
                if (widget.item.kind == MediaKind.audio)
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.album_outlined,
                              size: 100,
                              color: Color(0xFFD4EF88),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              widget.item.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${widget.item.artist} · ${widget.item.album}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_error != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      color: Colors.black87,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('返回片库'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((_buffering || _voice?.preparing == true) && _error == null)
                  const Center(child: _Ring()),
                if (_voice?.active == true && !_systemPip)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: _controls ? 170 : 32,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          color: Colors.black87,
                          child: Text(
                            _voice!.preparing
                                ? '语音译配缓冲中 · 等待服务'
                                : _voice!.text.isEmpty
                                ? '译配中 · 服务声明保留音色'
                                : _voice!.text,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xffffe3ad),
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_watchAi.active &&
                    _watchAi.config.subtitles &&
                    _watchAi.currentText.isNotEmpty)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom:
                        (_controls ? 168 : 36) +
                        MediaQuery.paddingOf(context).bottom,
                    child: IgnorePointer(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .72),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _watchAi.currentText,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (_watchAi.translation != null) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      _watchAi.translation!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFFFE3AD),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_systemPip && Platform.isIOS && _foreground)
                  Center(
                    child: FilledButton(
                      onPressed: () =>
                          PlaybackWindow.channel.invokeMethod('pip.stop'),
                      child: const Text('恢复到应用内播放'),
                    ),
                  ),
                if (!_systemPip && !_locked)
                  AnimatedOpacity(
                    opacity: _controls ? 1 : 0,
                    duration: const Duration(milliseconds: 240),
                    curve: WowMotion.page,
                    child: IgnorePointer(
                      ignoring: !_controls,
                      child: _controlsLayer(),
                    ),
                  ),
                if (_seekPreview != null)
                  Center(
                    child: IgnorePointer(
                      child: _gestureBadge(
                        '${playbackTime(_seekPreview!)}  /  ${playbackTime(_duration)}\n'
                        '${_seekPreview! >= _position ? '+' : ''}${(_seekPreview! - _position).round()} 秒 · 松手跳转',
                      ),
                    ),
                  ),
                if (_locked)
                  Positioned(
                    right: 20,
                    top: 24 + MediaQuery.paddingOf(context).top,
                    child: Semantics(
                      label: '触控已锁定，长按解锁',
                      button: true,
                      child: Tooltip(
                        message: '双指长按画面或长按此处解锁 · L / Esc',
                        child: GestureDetector(
                          onLongPress: _toggleScreenLock,
                          child: _gestureBadge('🔒  长按解锁'),
                        ),
                      ),
                    ),
                  ),
                if (!_introDone && _error == null)
                  CinemaEntrance(
                    style: _prefs.entrance,
                    title: widget.item.displayTitle,
                    onComplete: _finishEntrance,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gestureBadge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 14),
    ),
  );

  Widget _controlsLayer() {
    if (_window.mini)
      return Stack(
        children: [
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _togglePlay,
                    tooltip: '播放／暂停',
                    icon: Icon(
                      _playbackRunning ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    onPressed: _miniPlayer,
                    tooltip: '恢复播放器',
                    icon: const Icon(Icons.open_in_full, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: '停止并关闭',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB3000000),
                  Colors.transparent,
                  Colors.transparent,
                  Color(0xCC000000),
                ],
                stops: [0, 0.22, 0.62, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16 + MediaQuery.paddingOf(context).left,
          top: 12 + MediaQuery.paddingOf(context).top,
          right: 16 + MediaQuery.paddingOf(context).right,
          child: _topBar(),
        ),
        Center(
          child: AnimatedScale(
            scale: _playbackRunning ? 0.001 : 1,
            duration: const Duration(milliseconds: 220),
            curve: WowMotion.snappy,
            child: Pressable(
              onTap: _togglePlay,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.44),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12 + MediaQuery.paddingOf(context).left,
          right: 12 + MediaQuery.paddingOf(context).right,
          bottom: 12 + MediaQuery.paddingOf(context).bottom,
          child: _controlBar(),
        ),
      ],
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Pressable(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.35),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WowType.display(
                  19,
                  FontWeight.w500,
                  spacing: -0.5,
                  height: 1.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_privacy.routeLabel} · ${_privacy.blocked
                    ? '敏感内容外放静音'
                    : _muted
                    ? '已静音 · 双击画面恢复'
                    : '${_volume.round()}%'}'
                ' · ${_privacy.sensitive
                    ? '本片敏感标记'
                    : _sensitiveClient == null
                    ? '仅检查内容标记'
                    : _scanUnavailable
                    ? '画面检测不可用'
                    : '本机抽帧检测'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WowType.monoLabel(
                  8.5,
                  color: Colors.white.withValues(alpha: 0.55),
                  spacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: '播放工具',
          icon: const Icon(Icons.more_horiz, color: Colors.white),
          onSelected: (value) async {
            _hideTimer?.cancel();
            switch (value) {
              case 'lock':
                _toggleScreenLock();
              case 'sensitive':
                _detectSensitive();
              case 'frame':
                await _saveFrame();
              case 'frames':
                await _showFrames();
              case 'ab':
                await _markLoop();
              case 'clear':
                setState(() => _ab.clear());
                _message('AB 循环已停止');
              case 'mini':
                await _miniPlayer();
              case 'preferences':
                await configurePlayback(context);
              case 'voice-config':
                await configureVoiceTranslation(context);
              case 'voice':
                await _startDubbing();
              case 'voice-stop':
                await _stopDubbing();
            }
            if (mounted) _reveal();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'lock', child: Text('锁定触控，继续播放 · L')),
            PopupMenuItem(
              value: 'sensitive',
              enabled: !_privacy.sensitive,
              child: Text(_privacy.sensitive ? '本片敏感内容保护已启用' : '将本片标记为敏感内容'),
            ),
            if (widget.item.kind != MediaKind.audio)
              const PopupMenuItem(value: 'frame', child: Text('收藏当前精彩帧 · S')),
            const PopupMenuItem(value: 'frames', child: Text('本片精彩帧收藏')),
            if (!widget.isLive)
              PopupMenuItem(
                value: 'ab',
                child: Text(
                  _ab.a == null || _ab.enabled ? '标记 A 点 · B' : '标记 B 点并循环 · B',
                ),
              ),
            if (_ab.a != null)
              const PopupMenuItem(value: 'clear', child: Text('清除 AB 循环')),
            if (widget.item.kind != MediaKind.audio)
              PopupMenuItem(
                value: 'mini',
                child: Text(PlaybackWindow.desktop ? '置顶小窗' : '系统画中画'),
              ),
            const PopupMenuItem(value: 'preferences', child: Text('放映与后台播放设置')),
            if (!widget.isLive &&
                widget.item.kind != MediaKind.audio &&
                widget.item.aiAllowed)
              PopupMenuItem(
                value: _voice?.active == true ? 'voice-stop' : 'voice',
                child: Text(
                  _voice?.active == true ? '停止译配，恢复原声' : '开启语音译配 · 实验性',
                ),
              ),
            if (widget.item.aiAllowed)
              const PopupMenuItem(
                value: 'voice-config',
                child: Text('配置语音译配 API'),
              ),
          ],
        ),
        if (widget.item.kind != MediaKind.audio)
          PopupMenuButton<String>(
            tooltip: '字幕与轨道',
            icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
            onSelected: (value) async {
              _hideTimer?.cancel();
              switch (value) {
                case 'tracks':
                  await _selectSubtitle();
                case 'import':
                  await _importSubtitle();
                case 'nearby':
                  await _nearbySubtitles();
                case 'online':
                  await _findSubtitle();
              }
              if (mounted) _reveal();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'tracks', child: Text('内嵌与已加载字幕轨道')),
              PopupMenuItem(value: 'nearby', child: Text('缓存与同目录字幕')),
              PopupMenuItem(value: 'import', child: Text('导入本地字幕文件')),
              PopupMenuItem(value: 'online', child: Text('搜索在线字幕')),
            ],
          ),
        if (widget.item.kind != MediaKind.audio && widget.item.aiAllowed)
          IconButton(
            tooltip: 'AI 字幕与小映陪看',
            onPressed: _showCompanion,
            icon: Icon(
              Icons.face_3_outlined,
              color: _watchAi.config.enabled
                  ? const Color(0xFFFFE3AD)
                  : Colors.white,
              size: 24,
            ),
          ),
        if (widget.isLive) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xFFD5372F),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'LIVE',
                  style: WowType.monoLabel(
                    8,
                    color: Colors.white,
                    spacing: 1.6,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (MediaQuery.sizeOf(context).width >= 600)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              color: Colors.white.withValues(alpha: 0.06),
            ),
            child: Text(
              'LIBMPV',
              style: WowType.monoLabel(
                8,
                color: Colors.white.withValues(alpha: 0.75),
                spacing: 1.6,
              ),
            ),
          ),
      ],
    );
  }

  Widget _controlBar() {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return MouseRegion(
      onEnter: (_) {
        _hoverBar = true;
        _hideTimer?.cancel();
      },
      onExit: (_) {
        _hoverBar = false;
        _scheduleHide();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xE60C0E14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (_prefs.meter)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Tooltip(
                      message: _voice?.active == true
                          ? '译音 PCM 音频电平'
                          : '原片 PCM 采样的 RMS 音频电平',
                      child: SizedBox(
                        width: compact ? 46 : 80,
                        height: 14,
                        child: _audioLevelValue == null
                            ? const Text(
                                '电平 —',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              )
                            : Semantics(
                                label:
                                    '音频电平 ${((_audioLevelValue ?? 0) * 100).round()}%',
                                child: LinearProgressIndicator(
                                  value: _audioLevelValue,
                                  backgroundColor: Colors.white12,
                                  color: Colors.white70,
                                  minHeight: 4,
                                ),
                              ),
                      ),
                    ),
                  ),
                if (widget.isLive) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFD5372F),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'LIVE',
                    style: WowType.monoLabel(
                      9.5,
                      color: Colors.white.withValues(alpha: 0.85),
                      spacing: 1.6,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '直播中',
                    style: WowType.monoLabel(
                      9.5,
                      color: Colors.white.withValues(alpha: 0.38),
                      spacing: 0.8,
                    ),
                  ),
                ] else ...[
                  Text(
                    _fmt(_position),
                    style: WowType.monoLabel(
                      9.5,
                      color: Colors.white.withValues(alpha: 0.72),
                      spacing: 0.8,
                    ),
                  ),
                ],
                const Spacer(),
                if (_ab.a != null)
                  Flexible(
                    child: Text(
                      _ab.enabled
                          ? 'AB ${playbackTime(_ab.a!)}–${playbackTime(_ab.b!)}'
                          : 'A ${playbackTime(_ab.a!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xffffe3ad),
                        fontSize: 10,
                      ),
                    ),
                  ),
                if (!widget.isLive)
                  Text(
                    '-${_fmt((_duration - _position).clamp(0, _duration))}',
                    style: WowType.monoLabel(
                      9.5,
                      color: Colors.white.withValues(alpha: 0.45),
                      spacing: 0.8,
                    ),
                  ),
              ],
            ),
            if (!widget.isLive) ...[const SizedBox(height: 8), _scrubber()],
            const SizedBox(height: 10),
            Row(
              children: [
                _tool(
                  _playbackRunning
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  _togglePlay,
                  big: true,
                ),
                if (!widget.isLive) ...[
                  const SizedBox(width: 6),
                  _tool(Icons.replay_10_rounded, () => _seekBy(-10)),
                  const SizedBox(width: 4),
                  _tool(Icons.forward_30_rounded, () => _seekBy(30)),
                ],
                if (compact)
                  _tool(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    _toggleMute,
                  ),
                if (!compact) ...[
                  const SizedBox(width: 16),
                  _tool(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    () {
                      _toggleMute();
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 120,
                        child: _VolumeBar(
                          value: _volume,
                          onChanged: (v) {
                            _changeVolume(v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                PopupMenuButton<double>(
                  tooltip: '播放速度',
                  icon: const Icon(Icons.speed, color: Colors.white, size: 20),
                  onSelected: (v) async {
                    if (_voice?.active == true) await _stopDubbing();
                    await _player.setRate(v);
                  },
                  itemBuilder: (_) => [
                    for (final rate in [0.75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem(value: rate, child: Text('${rate}x')),
                  ],
                ),
                _tool(
                  (_mobileFullscreen || _window.fullscreen)
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  _toggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrubber() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final ratio = _duration <= 0
            ? 0.0
            : (_position / _duration).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _seekTo(d.localPosition.dx / w * _duration);
          },
          onHorizontalDragUpdate: (d) {
            _seekTo(d.localPosition.dx / w * _duration);
          },
          child: SizedBox(
            height: 16,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [WowColors.accent2, WowColors.accent],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (w * ratio - 6).clamp(0, w - 12),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tool(IconData icon, VoidCallback onTap, {bool big = false}) {
    return Semantics(
      button: true,
      label: icon == Icons.pause_rounded
          ? '暂停'
          : icon == Icons.play_arrow_rounded
          ? '播放'
          : icon == Icons.replay_10_rounded
          ? '后退十秒'
          : icon == Icons.forward_30_rounded
          ? '前进三十秒'
          : icon == Icons.fullscreen_rounded ||
                icon == Icons.fullscreen_exit_rounded
          ? '切换全屏'
          : icon == Icons.volume_off_rounded
          ? '取消静音'
          : '静音',
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: big
              ? const BoxDecoration(shape: BoxShape.circle, color: Colors.white)
              : null,
          child: Icon(
            icon,
            size: big ? 24 : 18,
            color: big ? Colors.black : Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  String _fmt(double s) {
    final total = s.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          onHorizontalDragUpdate: (d) =>
              onChanged((d.localPosition.dx / c.maxWidth * 100).clamp(0, 100)),
          onTapDown: (d) =>
              onChanged((d.localPosition.dx / c.maxWidth * 100).clamp(0, 100)),
          child: SizedBox(
            height: 16,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 2,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                FractionallySizedBox(
                  widthFactor: value / 100,
                  child: Container(
                    height: 2,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Positioned(
                  left: (c.maxWidth * value / 100 - 4).clamp(0, c.maxWidth - 8),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Ring extends StatefulWidget {
  const _Ring();
  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Transform.rotate(
        angle: _c.value * 6.283,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [Colors.transparent, WowColors.accent, WowColors.accent2],
            ),
          ),
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
