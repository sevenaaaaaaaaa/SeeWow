import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 在线播放的磁盘缓存与 demuxer 缓冲。
///
/// 在线源的慢分两段：起播前「选错线路」（见 line_quality.dart），和播放中
/// 「卡住 / 拖动后重新下载」。这一段管后者：让 libmpv 把已经下过的分片写到
/// 磁盘，并把前向缓冲抬到 30 秒——拖动、回看、断线重连时不必从头再拉。
///
/// 属性全部通过 setProperty 交给 libmpv；这版引擎不认识某个键时只跳过，
/// 不会影响播放。所有阈值都写在这里，真机对比时只改这一处。
class StreamCache {
  const StreamCache._();

  /// 磁盘缓存上限：超过就按「最久没动过」先删。
  static const int maxBytes = 512 << 20;

  /// 前向缓冲秒数。太小会卡，太大则起播前要等更久。
  static const int readAheadSeconds = 30;

  /// demuxer 内存缓冲：96 MiB 前向、24 MiB 回看。
  static const int demuxerMaxBytes = 96 << 20;

  static bool isNetwork(String locator) =>
      locator.startsWith('http://') || locator.startsWith('https://');

  /// 交给 libmpv 的属性表。值是 mpv 能解析的字符串。
  static Map<String, String> properties({
    required Directory directory,
    int readAhead = readAheadSeconds,
    int demuxerBytes = demuxerMaxBytes,
  }) => {
    'cache-on-disk': 'yes',
    'cache-dir': directory.path,
    'cache-secs': '$readAhead',
    'demuxer-readahead-secs': '$readAhead',
    'demuxer-max-bytes': '$demuxerBytes',
    'demuxer-max-back-bytes': '${demuxerBytes ~/ 4}',
  };

  /// 建目录并清到上限以内。
  ///
  /// [root] 为测试注入；生产传 null，落到系统的应用缓存目录。
  /// 拿不到目录（插件缺失、权限）时返回 null——缓存只是加速，不该拦住播放。
  static Future<Directory?> prepare({Directory? root, int cap = maxBytes}) async {
    try {
      var dir = root;
      if (dir == null) {
        final base = await getApplicationCacheDirectory();
        dir = Directory('${base.path}/stream-cache');
      }
      if (!await dir.exists()) await dir.create(recursive: true);
      await trim(dir, cap: cap);
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// 把目录压到 [maxBytes] 以内：按最后修改时间从旧到新删。
  /// 返回删掉的文件数，方便日志与测试。
  static Future<int> trim(Directory dir, {int cap = maxBytes}) async {
    if (!await dir.exists()) return 0;
    final entries = <({File file, int size, DateTime modified})>[];
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        entries.add((file: entity, size: stat.size, modified: stat.modified));
        total += stat.size;
      } catch (_) {
        // 正在写入的分片读不到大小就跳过，下一轮再算。
      }
    }
    if (total <= cap) return 0;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    var removed = 0;
    for (final entry in entries) {
      if (total <= cap) break;
      try {
        await entry.file.delete();
        total -= entry.size;
        removed++;
      } catch (_) {}
    }
    return removed;
  }

  /// 应用到播放器。[set] 是 libmpv 的 setProperty；任何一个键失败都只跳过。
  static Future<void> apply({
    required bool network,
    required Future<void> Function(String key, String value) set,
    Directory? root,
  }) async {
    if (!network) return;
    final dir = await prepare(root: root);
    if (dir == null) return;
    for (final entry in properties(directory: dir).entries) {
      try {
        await set(entry.key, entry.value);
      } catch (_) {
        // 这版 libmpv 不认识这个键：跳过，别把播放拖下水。
      }
    }
  }
}
