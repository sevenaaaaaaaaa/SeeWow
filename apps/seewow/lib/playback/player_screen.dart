import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../design/pressable.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.item, this.startAt, this.isLive = false});
  final MediaItem item;
  final double? startAt;
  final bool isLive;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _focus = FocusNode();
  Timer? _hideTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playSub;

  double _position = 0;
  double _duration = 0;
  bool _playing = false;
  bool _controls = true;
  bool _muted = false;
  bool _buffering = true;
  bool _hoverBar = false;

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'SeeWow',
        ready: null,
      ),
    );
    _controller = VideoController(_player);
    _posSub = _player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p.inMilliseconds / 1000);
    });
    _durSub = _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d.inMilliseconds / 1000);
    });
    _playSub = _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
    _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    _open();
    _scheduleHide();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  Future<void> _open() async {
    await _player.open(
      Media(
        widget.item.locator,
        httpHeaders: widget.item.httpHeaders.isEmpty ? null : widget.item.httpHeaders,
      ),
      play: true,
    );
    if (widget.isLive) {
      await _player.setVolume(90);
      return;
    }
    final start = widget.startAt ?? widget.item.position;
    if (start > 5) await _player.seek(Duration(milliseconds: (start * 1000).round()));
    await _player.setVolume(90);
  }

  void _scheduleHide() {
    if (Platform.environment['SEEWOW_KEEP_CONTROLS'] == '1') return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_hoverBar) setState(() => _controls = false);
    });
  }

  void _reveal() {
    setState(() => _controls = true);
    _scheduleHide();
  }

  void _togglePlay() {
    _player.playOrPause();
    _reveal();
  }

  void _seekBy(double seconds) {
    if (widget.isLive) return;
    final target = (_position + seconds).clamp(0, _duration);
    _player.seek(Duration(milliseconds: (target * 1000).round()));
    _reveal();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _player.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
              _player.setVolume(((_player.state.volume + 5).clamp(0, 100)));
              _reveal();
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowDown:
              _player.setVolume(((_player.state.volume - 5).clamp(0, 100)));
              _reveal();
              return KeyEventResult.handled;
            case LogicalKeyboardKey.keyM:
              _muted = !_muted;
              _player.setVolume(_muted ? 0 : 90);
              _reveal();
              return KeyEventResult.handled;
            case LogicalKeyboardKey.escape:
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: _controls ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) {
            if (!_controls) _reveal();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_controls) {
                setState(() => _controls = false);
                _hideTimer?.cancel();
              } else {
                _reveal();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(controller: _controller, controls: NoVideoControls, fill: Colors.black),
                if (_buffering)
                  const Center(child: _Ring()),
                AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 240),
                  curve: WowMotion.page,
                  child: IgnorePointer(
                    ignoring: !_controls,
                    child: _controlsLayer(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlsLayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB3000000), Colors.transparent, Colors.transparent, Color(0xCC000000)],
              stops: [0, 0.22, 0.62, 1],
            ),
          ),
        ),
        Positioned(left: 26, top: 22, right: 26, child: _topBar()),
        Center(
          child: AnimatedScale(
            scale: _playing ? 0.001 : 1,
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
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white),
              ),
            ),
          ),
        ),
        Positioned(left: 22, right: 22, bottom: 22, child: _controlBar()),
      ],
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Pressable(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.35)),
            child: const Icon(Icons.close_rounded, size: 17, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.displayTitle, style: WowType.display(19, FontWeight.w500, spacing: -0.5, height: 1.0)),
            const SizedBox(height: 2),
            Text(
              widget.isLive
                  ? '直播流  ·  LIVE STREAM'
                  : [if (widget.item.year != null) '${widget.item.year}', widget.item.badgeText].where((s) => s.isNotEmpty).join('  ·  ').toUpperCase(),
              style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.55), spacing: 1.4),
            ),
          ],
        ),
        const Spacer(),
        if (widget.isLive) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: const Color(0xFFD5372F)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
              const SizedBox(width: 5),
              Text('LIVE', style: WowType.monoLabel(8, color: Colors.white, spacing: 1.6).copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.16)), color: Colors.white.withValues(alpha: 0.06)),
          child: Text('LIBMPV', style: WowType.monoLabel(8, color: Colors.white.withValues(alpha: 0.75), spacing: 1.6)),
        ),
      ],
    );
  }

  Widget _controlBar() {
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 26, offset: const Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (widget.isLive) ...[
                  Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFD5372F))),
                  const SizedBox(width: 7),
                  Text('LIVE', style: WowType.monoLabel(9.5, color: Colors.white.withValues(alpha: 0.85), spacing: 1.6)),
                  const SizedBox(width: 10),
                  Text('直播中', style: WowType.monoLabel(9.5, color: Colors.white.withValues(alpha: 0.38), spacing: 0.8)),
                ] else ...[
                  Text(_fmt(_position), style: WowType.monoLabel(9.5, color: Colors.white.withValues(alpha: 0.72), spacing: 0.8)),
                ],
                const Spacer(),
                if (!widget.isLive)
                  Text('-${_fmt((_duration - _position).clamp(0, _duration))}', style: WowType.monoLabel(9.5, color: Colors.white.withValues(alpha: 0.45), spacing: 0.8)),
              ],
            ),
            if (!widget.isLive) ...[
              const SizedBox(height: 8),
              _scrubber(),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _tool(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, _togglePlay, big: true),
                if (!widget.isLive) ...[
                  const SizedBox(width: 6),
                  _tool(Icons.replay_10_rounded, () => _seekBy(-10)),
                  const SizedBox(width: 4),
                  _tool(Icons.forward_30_rounded, () => _seekBy(30)),
                ],
                const SizedBox(width: 16),
                _tool(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, () {
                  setState(() => _muted = !_muted);
                  _player.setVolume(_muted ? 0 : 90);
                }),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 120,
                      child: _VolumeBar(
                        value: _player.state.volume,
                        onChanged: (v) {
                          setState(() => _muted = v == 0);
                          _player.setVolume(v);
                        },
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                _tool(Icons.fullscreen_rounded, () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrubber() {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final ratio = _duration <= 0 ? 0.0 : (_position / _duration).clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _player.seek(Duration(milliseconds: (d.localPosition.dx / w * _duration * 1000).round())),
        onHorizontalDragUpdate: (d) => _player.seek(Duration(milliseconds: (d.localPosition.dx / w * _duration * 1000).round())),
        child: SizedBox(
          height: 16,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(height: 3, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.white.withValues(alpha: 0.16))),
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(colors: [WowColors.accent2, WowColors.accent]),
                  ),
                ),
              ),
              Positioned(
                left: (w * ratio - 6).clamp(0, w - 12),
                child: Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _tool(IconData icon, VoidCallback onTap, {bool big = false}) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: big ? 42 : 32,
        height: big ? 42 : 32,
        decoration: big ? const BoxDecoration(shape: BoxShape.circle, color: Colors.white) : null,
        child: Icon(icon, size: big ? 24 : 18, color: big ? Colors.black : Colors.white.withValues(alpha: 0.85)),
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
    return LayoutBuilder(builder: (context, c) {
      return GestureDetector(
        onHorizontalDragUpdate: (d) => onChanged((d.localPosition.dx / c.maxWidth * 100).clamp(0, 100)),
        onTapDown: (d) => onChanged((d.localPosition.dx / c.maxWidth * 100).clamp(0, 100)),
        child: SizedBox(
          height: 16,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(height: 2, color: Colors.white.withValues(alpha: 0.18)),
              FractionallySizedBox(widthFactor: value / 100, child: Container(height: 2, color: Colors.white.withValues(alpha: 0.8))),
              Positioned(
                left: (c.maxWidth * value / 100 - 4).clamp(0, c.maxWidth - 8),
                child: Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _Ring extends StatefulWidget {
  const _Ring();
  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

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
          width: 30, height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [Colors.transparent, WowColors.accent, WowColors.accent2]),
          ),
          child: Center(child: Container(width: 26, height: 26, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black))),
        ),
      ),
    );
  }
}