import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';

/// 一条线路的一次测量：首包用了多少毫秒，什么时候测的。
class LineEntry {
  const LineEntry({required this.millis, required this.at});

  final int millis;
  final DateTime at;

  Map<String, Object?> toJson() => {'ms': millis, 'at': at.toIso8601String()};

  static LineEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final millis = raw['ms'];
    final at = DateTime.tryParse('${raw['at'] ?? ''}');
    if (millis is! num || at == null) return null;
    return LineEntry(millis: millis.round(), at: at);
  }
}

/// 「哪条线路快」的本地记忆：作品 → 站点 → 首包毫秒数。
///
/// 采集站给的是一个作品好几条线路，线路之间快慢能差十倍。每次都从排序第一
/// 条开始试，等于每次都赌同一匹马。这里把上次测到的结果留下来：6 小时内再
/// 播同一个作品，直接走上次最快的那条，不再重新赌。
///
/// 只存测量结果，不存地址——地址会过期，站点 id 不会。
class LineMemory {
  LineMemory({this.directory, this.ttl = const Duration(hours: 6)});

  /// App 内存里共享的一份；测试与工具可以自己 new 一个带临时目录的实例。
  static final LineMemory shared = LineMemory();

  final Directory? directory;
  final Duration ttl;
  final Map<String, Map<String, LineEntry>> _entries = {};

  Future<void>? _loading;
  bool _loaded = false;

  File? _file;

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      Directory? dir = directory;
      if (dir == null) {
        try {
          // 读目录只是加速，不该拖住起播：插件缺失或卡住都在 400ms 内放弃，
          // 退化成只记在内存里。
          dir = await getApplicationSupportDirectory().timeout(
            const Duration(milliseconds: 400),
          );
        } catch (_) {
          dir = null;
        }
      }
      if (dir == null) return;
      _file = File('${dir.path}/line_quality.json');
      if (!await _file!.exists()) return;
      final raw = jsonDecode(await _file!.readAsString());
      if (raw is! Map) return;
      final works = raw['works'];
      if (works is! Map) return;
      for (final work in works.entries) {
        final sites = work.value;
        if (sites is! Map) continue;
        final line = <String, LineEntry>{};
        for (final site in sites.entries) {
          final entry = LineEntry.fromJson(site.value);
          if (entry != null) line['${site.key}'] = entry;
        }
        if (line.isNotEmpty) _entries['${work.key}'] = line;
      }
    } catch (_) {
      // 记忆读不出来只是少一次加速，不该影响起播。
    } finally {
      _loaded = true;
    }
  }

  /// 上次最快的站点 id；过期或没测过返回 null。
  String? bestSite(String workId) {
    final line = _entries[workId];
    if (line == null || line.isEmpty) return null;
    final now = DateTime.now();
    String? winner;
    var fastest = 1 << 30;
    for (final entry in line.entries) {
      if (now.difference(entry.value.at) > ttl) continue;
      if (entry.value.millis < fastest) {
        fastest = entry.value.millis;
        winner = entry.key;
      }
    }
    return winner;
  }

  Future<void> record(String workId, String siteId, int millis) async {
    await ensureLoaded();
    _entries.putIfAbsent(workId, () => {})[siteId] = LineEntry(
      millis: millis,
      at: DateTime.now(),
    );
    await _save();
  }

  /// 这条线路上次刚失败：把记录删掉，下次重新测。
  Future<void> forget(String workId, String siteId) async {
    await ensureLoaded();
    _entries[workId]?.remove(siteId);
    await _save();
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final works = <String, Object?>{};
      for (final work in _entries.entries) {
        works[work.key] = {
          for (final site in work.value.entries) site.key: site.value.toJson(),
        };
      }
      await file.writeAsString(
        jsonEncode({'version': 1, 'works': works}),
        flush: true,
      );
    } catch (_) {
      // 写不进去只影响下一次的排序，不影响这一次的播放。
    }
  }
}

/// 量一条线路的首包时间。返回 null 表示测不出来（超时 / 4xx / 不是 http）。
abstract class LineProbe {
  Future<int?> measure(MediaItem item, {Duration budget});
}

/// 真实现：带 Range 的 GET，只要头部，不下载整集。
///
/// 这一步同时把 DNS、TLS 和 CDN 边缘预热了——播放器随后请求同一地址时，握手
/// 已经发生过，首帧会快一截。
class HttpLineProbe implements LineProbe {
  const HttpLineProbe();

  @override
  Future<int?> measure(
    MediaItem item, {
    Duration budget = const Duration(milliseconds: 1400),
  }) async {
    final uri = Uri.tryParse(item.locator);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    final client = HttpClient()..connectionTimeout = budget;
    final watch = Stopwatch()..start();
    try {
      final request = await client.getUrl(uri).timeout(budget);
      item.httpHeaders.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      final response = await request.close().timeout(budget);
      final firstByte = watch.elapsedMilliseconds;
      if (response.statusCode >= 400) return null;
      // 只把头部读掉，不等整集体下载完。
      unawaited(response.drain<void>().timeout(budget).catchError((_) {}));
      return firstByte;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
