import 'dart:io';

import 'package:media_kit/media_kit.dart';

import '../domain/media_item.dart';
import 'chapters.dart';

/// 一次加载的结果。source 说明这批章节是谁给的——UI 要能说"这部片没有章节"，
/// 而不是把"没读到"和"真的没有"混成同一件事。
class ChapterLoad {
  const ChapterLoad({required this.chapters, required this.source});

  final List<Chapter> chapters;

  /// cache | mpv | ffprobe | none
  final String source;

  bool get isEmpty => chapters.isEmpty;
}

/// ffprobe 抽章节。用于桌面端与离线校验，**不随 app 分发**：
/// iOS 里没有这个二进制，CI 上也不一定有。所以它排在 mpv 后面，是兜底不是主路。
class FfprobeChapterSource {
  const FfprobeChapterSource({
    this.binary = 'ffprobe',
    this.timeout = const Duration(seconds: 8),
  });

  final String binary;
  final Duration timeout;

  static bool? _available;

  /// 二进制到底在不在。只测一次，别每次开片都 spawn 一个进程去问。
  static Future<bool> available({String binary = 'ffprobe'}) async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      final result = await Process.run(
        binary,
        ['-version'],
      ).timeout(const Duration(seconds: 5));
      _available = result.exitCode == 0;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  Future<List<Chapter>> read(MediaItem item) async {
    if (!await available(binary: binary)) return const [];
    // 只对真实存在的本地文件跑：http(s) 会让 ffprobe 去拉整条流，代价不可控；
    // 路径不存在只会得到空结果，白开一个进程。两条都先挡掉。
    final uri = Uri.tryParse(item.locator);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return const [];
    }
    if (!await File(item.locator).exists()) return const [];
    try {
      final result = await Process.run(binary, [
        '-v',
        'error',
        '-show_chapters',
        '-of',
        'json',
        item.locator,
      ]).timeout(timeout);
      if (result.exitCode != 0) return const [];
      return parseFfprobeChapters(result.stdout as String);
    } catch (_) {
      return const [];
    }
  }
}

/// mpv 抽章节：**生产路径**。容器里的章节本来就在 libmpv 手里，
/// 读一个属性就行，不需要任何外部二进制，也不需要重新打开文件。
Future<List<Chapter>> readMpvChapters(
  Player player, {
  required double duration,
}) async {
  try {
    // media_kit 的公开 API 没有 getProperty，这里用 dynamic 拿 mpv 的原始属性；
    // 拿不到就是没有章节，不影响播放。
    final raw = await (player.platform as dynamic)?.getProperty('chapter-list');
    return parseMpvChapters(raw as String?, duration: duration);
  } catch (_) {
    return const [];
  }
}

/// 本次会话里已经问过 ffprobe 的条目：没有章节的片子不必每次开都 spawn 一遍。
final Set<String> _ffprobeTried = {};

/// 组合取章节：缓存 → mpv → ffprobe。
///
/// 顺序有理由：缓存最便宜；mpv 已经在播这部片，读属性几乎免费且跨平台；
/// ffprobe 要开进程、且 iOS 上根本不存在，所以放最后、且每个条目每会话只试一次。
Future<ChapterLoad> loadChapters(
  MediaItem item, {
  Player? player,
  ChapterStore? store,
  bool allowFfprobe = true,
}) async {
  final chapters = store ?? ChapterStore.I;

  final cached = await chapters.read(item);
  if (cached != null && cached.isNotEmpty) {
    return ChapterLoad(chapters: cached, source: 'cache');
  }

  if (player != null) {
    final fromMpv = await readMpvChapters(player, duration: item.duration);
    if (fromMpv.isNotEmpty) {
      await chapters.write(item, fromMpv);
      return ChapterLoad(chapters: fromMpv, source: 'mpv');
    }
  }

  final key = chapters.keyFor(item);
  if (allowFfprobe && !_ffprobeTried.contains(key)) {
    _ffprobeTried.add(key);
    final fromProbe = await const FfprobeChapterSource().read(item);
    if (fromProbe.isNotEmpty) {
      await chapters.write(item, fromProbe);
      return ChapterLoad(chapters: fromProbe, source: 'ffprobe');
    }
  }

  return const ChapterLoad(chapters: [], source: 'none');
}
