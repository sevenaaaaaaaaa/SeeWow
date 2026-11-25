import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/media_item.dart';
import 'trickplay.dart';

/// 真机取帧：一个常开的、静音的、无窗口播放器。
///
/// 实测（mpv 0.42，4K 293 MB 素材）：冷启动取一帧 292–448 ms，常开播放器
/// 42–67 ms。所以缓存构建必须复用同一个播放器，每帧只做 seek + 截图。
///
/// 视频输出不能省：libmpv 要有一个渲染目标才会"有当前帧"可截。这里挂一个
/// VideoController，不需要任何 Widget 出现在屏幕上。
class MediaKitTrickplaySource implements TrickplaySource {
  Player? _player;
  VideoController? _video;

  @override
  Future<void> open(MediaItem item) async {
    final player = Player(
      configuration: const PlayerConfiguration(
        muted: true,
        osc: false,
        title: 'SeeWow trickplay',
      ),
    );
    _player = player;
    _video = VideoController(player);
    await player.open(
      Media(item.locator, httpHeaders: item.httpHeaders),
      play: false,
    );

    // 让 mpv 自己缩到目标宽度：截图就已经是小图，省解码后的缩放与磁盘。
    // media_kit 的公开 API 里没有 setProperty，用 dynamic 是为了不把某个版本的
    // 内部类型写死在业务代码里；拿不到就退回原尺寸截图（帧会大，但不错）。
    try {
      final platform = player.platform;
      await (platform as dynamic)?.setProperty('vf', 'scale=160:-2');
    } catch (_) {}

    // 等第一帧渲染出来；等不到也继续——截图会自己等到有画面。
    try {
      await _video!.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {}
  }

  @override
  Future<Uint8List?> grab(double seconds) async {
    final player = _player;
    if (player == null) return null;
    await player.seek(Duration(milliseconds: (seconds * 1000).round()));

    // seek 是异步的：位置报告到位之后，再给渲染线程一口气。
    // 这里不等"精确帧"——缩略图只需要"这一桶里的一张画面"。
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(end)) {
      final position = player.state.position.inMilliseconds / 1000;
      if ((position - seconds).abs() < 0.1) break;
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    await Future<void>.delayed(const Duration(milliseconds: 12));
    try {
      return await player.screenshot(format: 'image/jpeg');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    final player = _player;
    _video = null;
    _player = null;
    // VideoController 自己没有 dispose：它的渲染资源挂在 Player 上，
    // 播放器一销毁，controller 的监听与平台对象跟着走（见 media_kit 源码注释）。
    try {
      await player?.dispose();
    } catch (_) {}
  }
}
