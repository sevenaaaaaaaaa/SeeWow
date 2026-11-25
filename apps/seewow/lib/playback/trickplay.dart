import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';

/// trickplay 缓存的落盘格式版本。
///
/// **改布局就把这个数 +1。** 读者看到别的版本一律判过期重建，不做兼容读：
/// 兼容读是一笔永久的税，只为了省一次几十秒的后台构建，不划算。
const int kTrickplayFormat = 1;

/// 采样间隔（秒）。800 px 宽的轨对 2 小时片正好 9 秒/像素，10 秒一帧已经不浪费。
const double kTrickplayInterval = 10;

/// 帧宽（像素）。160 px 的 jpeg 约 4 KB，2 小时片 720 帧约 3 MB。
const int kTrickplayWidth = 160;

/// 取帧的口子。测试注入假实现，真机由 MediaKitTrickplaySource 提供。
///
/// 这一层只承诺"给个时间点、还一张 jpeg"，不承诺精确到帧：缩略图的正确性
/// 标准是"这一桶里的一张画面"，不是"第 7201 帧"。所以拿不到就返回 null，
/// 构建器记一次失败，不会把整个缓存拖死。
abstract class TrickplaySource {
  Future<void> open(MediaItem item);
  Future<Uint8List?> grab(double seconds);
  Future<void> close();
}

/// 索引文件。帧不写元信息——帧号就是时间，元信息只有这一份。
class TrickplayManifest {
  const TrickplayManifest({
    required this.format,
    required this.key,
    required this.interval,
    required this.width,
    required this.duration,
    required this.total,
    required this.done,
    required this.missing,
    required this.state,
    required this.sourceSize,
    required this.sourceMtimeMs,
    required this.updatedAt,
  });

  final int format;
  final String key;
  final double interval;
  final int width;
  final double duration;
  final int total;
  final int done;
  final int missing;

  /// building（构建中/被中断）| ready（可用）| failed（取不到帧，别再试）
  final String state;
  final int sourceSize;
  final int sourceMtimeMs;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'v': format,
    'key': key,
    'interval': interval,
    'width': width,
    'duration': duration,
    'total': total,
    'done': done,
    'missing': missing,
    'state': state,
    'size': sourceSize,
    'mtime': sourceMtimeMs,
    'updated': updatedAt.toUtc().toIso8601String(),
  };

  static TrickplayManifest? fromJson(Map<String, dynamic> j) {
    try {
      return TrickplayManifest(
        format: j['v'] as int,
        key: j['key'] as String,
        interval: (j['interval'] as num).toDouble(),
        width: j['width'] as int,
        duration: (j['duration'] as num).toDouble(),
        total: j['total'] as int,
        done: j['done'] as int,
        missing: j['missing'] as int,
        state: j['state'] as String,
        sourceSize: j['size'] as int,
        sourceMtimeMs: j['mtime'] as int,
        updatedAt: DateTime.parse(j['updated'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  TrickplayManifest copyWith({
    int? done,
    int? missing,
    String? state,
    DateTime? updatedAt,
  }) => TrickplayManifest(
    format: format,
    key: key,
    interval: interval,
    width: width,
    duration: duration,
    total: total,
    done: done ?? this.done,
    missing: missing ?? this.missing,
    state: state ?? this.state,
    sourceSize: sourceSize,
    sourceMtimeMs: sourceMtimeMs,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 一次构建的结果，用来写日志和测试断言。
class TrickplayBuildResult {
  const TrickplayBuildResult({
    required this.state,
    required this.written,
    required this.reused,
    required this.missing,
  });
  final String state;
  final int written;
  final int reused;
  final int missing;

  @override
  String toString() =>
      'trickplay $state · 新写 $written · 复用 $reused · 缺 $missing';
}

/// 磁盘布局（**冻结**）：
///
///   支持目录/SeeWow/trickplay/条目号/
///     index.json          清单，原子写（.tmp 改名）
///     f/桶号.jpg          第 index 桶的帧，index = floor(seconds / 10)
///
/// key 只由条目身份决定（id + 定位符），不含体积与时间戳——否则源文件一变就
/// 换目录、旧目录永远没人删。体积与 mtime 存在清单里，用来判过期、原地重建。
class TrickplayCache {
  TrickplayCache({this.directory});

  static final TrickplayCache I = TrickplayCache();
  final Directory? directory;

  Future<Directory> _root() async {
    final dir =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/SeeWow/trickplay',
        );
    await dir.create(recursive: true);
    return dir;
  }

  /// 条目身份 → 16 位十六进制。不含体积/时间戳，避免孤儿目录。
  String keyFor(MediaItem item) => sha256
      .convert(utf8.encode('${item.id}|${item.locator}'))
      .toString()
      .substring(0, 16);

  Future<Directory> dirFor(String key) async {
    if (!RegExp(r'^[a-f0-9]{16}$').hasMatch(key)) {
      throw const FormatException('trickplay 标识无效');
    }
    final dir = Directory('${(await _root()).path}/$key');
    await dir.create(recursive: true);
    await Directory('${dir.path}/f').create(recursive: true);
    return dir;
  }

  Future<File> frameFile(String key, int index) async =>
      File('${(await dirFor(key)).path}/f/$index.jpg');

  static int totalFor(double duration) =>
      duration <= 0 ? 0 : (duration / kTrickplayInterval).ceil();

  /// 秒 → 桶号。轨上任何一点都能落到一个确定的桶。
  static int indexFor(double seconds, double duration) {
    final total = totalFor(duration);
    if (total == 0) return 0;
    return (seconds / kTrickplayInterval).floor().clamp(0, total - 1);
  }

  /// 桶号 → 采样时刻：**取桶中心**，最大误差 ±5 秒，比取桶首少一半。
  /// 最后一桶钳到片尾之前，免得 seek 到 EOF 拿到空帧。
  static double timeForIndex(int index, double duration) {
    final center = index * kTrickplayInterval + kTrickplayInterval / 2;
    return math.min(center, math.max(0, duration - 0.05));
  }

  Future<TrickplayManifest?> read(String key) async {
    try {
      final file = File('${(await dirFor(key)).path}/index.json');
      if (!await file.exists()) return null;
      if (await file.length() > 256 * 1024) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final manifest = TrickplayManifest.fromJson(
        Map<String, dynamic>.from(json),
      );
      if (manifest == null || manifest.format != kTrickplayFormat) return null;
      return manifest;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeManifest(TrickplayManifest manifest) async {
    final dir = await dirFor(manifest.key);
    final temp = File('${dir.path}/index.json.tmp');
    await temp.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    await temp.rename('${dir.path}/index.json');
  }

  /// 帧落盘：先写 .tmp 再改名。半截文件永远不会被当成一帧读出来。
  Future<void> writeFrame(String key, int index, Uint8List bytes) async {
    final file = await frameFile(key, index);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  /// 读一帧。桶号越界钳到两端；文件不在就是 null（不是抛异常）。
  Future<Uint8List?> readFrame(String key, int index) async {
    try {
      final file = await frameFile(key, index);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// 按秒取帧：拖到轨上任何一点，都能落到一个确定的桶。
  ///
  /// 这是缓存器对外的唯一读口——轨、雷达、以后的双指预览全走它。
  Future<Uint8List?> frameAt(MediaItem item, double seconds) async {
    final total = totalFor(item.duration);
    if (total == 0) return null;
    final index = indexFor(seconds, item.duration).clamp(0, total - 1);
    return readFrame(keyFor(item), index);
  }

  /// 已存在的帧号。断点续建靠它，不靠清单里的计数——计数会撒谎，文件不会。
  Future<Set<int>> existingFrames(String key) async {
    final dir = Directory('${(await dirFor(key)).path}/f');
    final done = <int>{};
    for (final entity in await dir.list().toList()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.jpg')) continue;
      final index = int.tryParse(name.substring(0, name.length - 4));
      if (index != null) done.add(index);
    }
    return done;
  }

  /// 过期判定：格式、间隔、宽度、时长、体积、mtime，任何一项对不上就重建。
  /// 体积/mtime 取不到（远端流、文件已删）时不参与判断，宁可用旧缓存也别反复重建。
  bool isStale(
    TrickplayManifest manifest, {
    required double duration,
    required int sourceSize,
    required int sourceMtimeMs,
  }) {
    if (manifest.format != kTrickplayFormat) return true;
    if (manifest.interval != kTrickplayInterval) return true;
    if (manifest.width != kTrickplayWidth) return true;
    if ((manifest.duration - duration).abs() > 1) return true;
    if (manifest.total != totalFor(duration)) return true;
    if (sourceSize != 0 &&
        manifest.sourceSize != 0 &&
        sourceSize != manifest.sourceSize) {
      return true;
    }
    if (sourceMtimeMs != 0 &&
        manifest.sourceMtimeMs != 0 &&
        sourceMtimeMs != manifest.sourceMtimeMs) {
      return true;
    }
    return false;
  }

  /// 清掉一个条目的缓存（重建前调用）。目录本身保留，省一次 mkdir。
  Future<void> clear(String key) async {
    final dir = await dirFor(key);
    for (final name in ['index.json', 'index.json.tmp']) {
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
    }
    final frames = Directory('${dir.path}/f');
    if (await frames.exists()) await frames.delete(recursive: true);
    await frames.create(recursive: true);
  }
}

/// 构建器：把一个条目的帧补齐。可断点续建、可中断、失败有上限。
class TrickplayBuilder {
  TrickplayBuilder({required this.cache, required this.openSource});

  final TrickplayCache cache;
  final Future<TrickplaySource> Function() openSource;

  /// 连续失败到这个数就放弃，并把 state 标成 failed：
  /// 一个取不到帧的解码器不该让队列永远重试同一部片。
  static const int failureLimit = 8;

  Future<TrickplayBuildResult> build(
    MediaItem item, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = TrickplayCache.totalFor(item.duration);
    if (total == 0) {
      return const TrickplayBuildResult(
        state: 'skipped',
        written: 0,
        reused: 0,
        missing: 0,
      );
    }

    final key = cache.keyFor(item);
    final stat = await _stat(item);
    var manifest = await cache.read(key);
    final stale =
        manifest == null ||
        cache.isStale(
          manifest,
          duration: item.duration,
          sourceSize: stat.size,
          sourceMtimeMs: stat.mtimeMs,
        );

    if (stale) {
      await cache.clear(key);
      manifest = null;
    }

    final done = await cache.existingFrames(key);
    if (!stale &&
        manifest != null &&
        manifest.missing == 0 &&
        done.length >= total) {
      return TrickplayBuildResult(
        state: manifest.state,
        written: 0,
        reused: done.length,
        missing: 0,
      );
    }

    var current =
        manifest ??
        TrickplayManifest(
          format: kTrickplayFormat,
          key: key,
          interval: kTrickplayInterval,
          width: kTrickplayWidth,
          duration: item.duration,
          total: total,
          done: done.length,
          missing: total - done.length,
          state: 'building',
          sourceSize: stat.size,
          sourceMtimeMs: stat.mtimeMs,
          updatedAt: DateTime.now().toUtc(),
        );
    await cache.writeManifest(current.copyWith(state: 'building'));

    var written = 0;
    var failures = 0;
    TrickplaySource? source;
    try {
      source = await openSource();
      await source.open(item);
      for (var index = 0; index < total; index++) {
        if (done.contains(index)) continue;
        if (isCancelled?.call() ?? false) {
          break;
        }
        final bytes = await source.grab(
          TrickplayCache.timeForIndex(index, item.duration),
        );
        if (bytes == null || bytes.isEmpty) {
          failures++;
          if (failures >= failureLimit) break;
          continue;
        }
        await cache.writeFrame(key, index, bytes);
        written++;
        done.add(index);
        current = current.copyWith(
          done: done.length,
          missing: total - done.length,
        );
        if (written % 60 == 0) {
          await cache.writeManifest(
            current.copyWith(
              done: done.length,
              missing: total - done.length,
              state: 'building',
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        }
        onProgress?.call(done.length, total);
      }
    } finally {
      try {
        await source?.close();
      } catch (_) {}
    }

    final failedHard = failures >= failureLimit && done.isEmpty;
    final state = failedHard
        ? 'failed'
        : (done.length >= total ? 'ready' : 'building');
    await cache.writeManifest(
      current.copyWith(
        done: done.length,
        missing: total - done.length,
        state: state,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    onProgress?.call(done.length, total);
    return TrickplayBuildResult(
      state: state,
      written: written,
      reused: done.length - written,
      missing: total - done.length,
    );
  }

  Future<({int size, int mtimeMs})> _stat(MediaItem item) async {
    try {
      final uri = Uri.tryParse(item.locator);
      if (uri != null && ['http', 'https'].contains(uri.scheme)) {
        return (size: item.fileSize, mtimeMs: 0);
      }
      final file = File(item.locator);
      if (!await file.exists()) return (size: 0, mtimeMs: 0);
      final stat = await file.stat();
      return (
        size: stat.size,
        mtimeMs: stat.modified.millisecondsSinceEpoch,
      );
    } catch (_) {
      return (size: 0, mtimeMs: 0);
    }
  }
}

/// 读缓存的内存层。拖动每秒会问 60 次，每次都读盘是浪费；
/// 24 帧 × 约 4 KB ≈ 96 KB 内存，换掉一整个拖动过程的磁盘读取。
class TrickplayReader {
  TrickplayReader({TrickplayCache? cache, this.capacity = 24})
    : cache = cache ?? TrickplayCache.I;

  static final TrickplayReader I = TrickplayReader();

  final TrickplayCache cache;
  final int capacity;

  /// 插入顺序即淘汰顺序：命中就把它挪到队尾。
  final Map<String, Uint8List> _memory = {};

  int get memoSize => _memory.length;

  Future<Uint8List?> at(MediaItem item, double seconds) async {
    final total = TrickplayCache.totalFor(item.duration);
    if (total == 0) return null;
    final key = cache.keyFor(item);
    final index = TrickplayCache.indexFor(seconds, item.duration);
    final memoKey = '$key/$index';

    final hit = _memory.remove(memoKey);
    if (hit != null) {
      _memory[memoKey] = hit;
      return hit;
    }
    final bytes = await cache.readFrame(key, index);
    if (bytes == null) return null;
    _memory[memoKey] = bytes;
    while (_memory.length > capacity) {
      _memory.remove(_memory.keys.first);
    }
    return bytes;
  }

  void clear() => _memory.clear();
}

/// 构建队列：串行、去重、进程内只跑一条。
///
/// 串行是刻意的——同时开两个 headless 播放器解码两个 4K 文件，用户正在看的
/// 那部片会掉帧。宁可排队 40 秒，也不要抢前台。
class TrickplayQueue {
  TrickplayQueue({TrickplayCache? cache}) : cache = cache ?? TrickplayCache.I;

  static final TrickplayQueue I = TrickplayQueue();
  final TrickplayCache cache;

  final Map<String, Future<void>> _jobs = {};
  Future<void> _tail = Future<void>.value();

  /// 已经排上/在跑就别重复排。返回的 Future 在本条做完时收尾。
  Future<void> start(MediaItem item, TrickplaySource Function() open) {
    final key = cache.keyFor(item);
    final running = _jobs[key];
    if (running != null) return running;

    final builder = TrickplayBuilder(
      cache: cache,
      openSource: () async => open(),
    );
    final job = _serial(() async {
      try {
        await builder.build(item);
      } catch (_) {
        // 后台任务不许把异常抛给调用方：首开是自动触发的，没人接得住。
      }
    });
    // 存的是"收尾版"：第二次 start 拿到的必须是同一个 Future 对象，
    // 否则调用方会以为排了两次队。
    // 这里必须写成块体：箭头体返回的是 Map.remove 的值，也就是 tracked 自己，
    // whenComplete 会去等它完成——自己等自己，队列直接卡死。
    final tracked = job.whenComplete(() {
      _jobs.remove(key);
    });
    _jobs[key] = tracked;
    return tracked;
  }

  Future<void> _serial(Future<void> Function() body) {
    final next = _tail.then((_) => body(), onError: (_) => body());
    _tail = next.catchError((_) {});
    return next;
  }

  bool isRunning(String key) => _jobs.containsKey(key);
  int get pending => _jobs.length;
}
