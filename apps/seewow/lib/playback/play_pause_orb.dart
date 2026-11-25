import 'package:flutter/material.dart';

import '../design/pressable.dart';

/// 画面中央的播放／暂停按钮。
///
/// 它属于画面，不属于底部控件条：暂停不该要求先把控件条调出来，再去底边
/// 找一个 44px 的小图标。播放时保持低透明度，免得一个实心黑圆压在人脸与
/// 字幕上；暂停时恢复满不透明，因为那一刻它是画面里唯一该被看见的东西。
class PlayPauseOrb extends StatelessWidget {
  const PlayPauseOrb({
    super.key,
    required this.playing,
    required this.onPressed,
  });

  final bool playing;
  final VoidCallback onPressed;

  /// 播放中：看得清是暂停键，又不会在画面上留一个硬圆。
  static const double playingOpacity = .26;
  static const double _size = 76;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedOpacity(
      key: const ValueKey('playPauseOrb.opacity'),
      opacity: playing ? playingOpacity : 1,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: Pressable(
        onTap: onPressed,
        focusRadius: _size / 2,
        child: Tooltip(
          message: playing ? '暂停' : '播放',
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.44),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
