import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';
import 'download_quality.dart';
import 'download_task.dart';

class ResolvedMedia {
  const ResolvedMedia(this.item, this.source);
  final MediaItem item;
  final MediaSource? source;
}

typedef DownloadItemResolver = Future<ResolvedMedia?> Function(String itemId);

class DownloadManager extends ChangeNotifier {
  DownloadManager({this.directory, this.storageDirectory, this.resolver});

  final Directory? directory;
  final Directory? storageDirectory;
  DownloadItemResolver? resolver;
  final List<DownloadTask> tasks = [];
  String? storagePath;
  int speedLimitKbps = 0;
  bool loaded = false;

  Future<void> _writes = Future.value();
  bool _pumping = false;
  final Set<String> _paused = {};
  final Set<String> _cancelled = {};
  final Map<String, DateTime> _lastNotify = {};
  final Map<String, List<(DateTime, int)>> _samples = {};

  int get activeCount => tasks.where((t) => t.isActive).length;
  int get completedCount => tasks.where((t) => t.isDone).length;
  int get offlineBytes =>
      tasks.where((t) => t.isDone).fold(0, (sum, t) => sum + t.totalBytes);

  DownloadTask? taskFor(String itemId) =>
      tasks.where((t) => t.itemId == itemId).firstOrNull;

  bool _fileExists(DownloadTask task) {
    final path = task.filePath;
    return path != null && File(path).existsSync();
  }

  /// Tasks whose file really sits on disk.
  ///
  /// The stored status is not trusted: a file at the final path means the bytes
  /// arrived, even when the status write was lost (app killed right after the
  /// rename). Conversely, a "completed" task whose file was moved away is not
  /// playable.
  List<DownloadTask> get playableTasks => [
    for (final task in tasks)
      if (_fileExists(task)) task,
  ];

  /// Whitespace and punctuation removed, Latin lower-cased; CJK kept as-is.
  static String _titleKey(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

  /// Cached task for an item: exact id first, then the same title under the
  /// same source, because a re-linked Plex/WebDAV source hands out new item
  /// ids while the downloaded file keeps its old title.
  DownloadTask? cachedTaskFor(MediaItem item) {
    final playable = playableTasks;
    for (final task in playable.reversed) {
      if (task.itemId == item.id) return task;
    }
    final key = _titleKey(item.displayTitle);
    if (key.isEmpty) return null;
    final candidates = playable
        .where((t) => _titleKey(t.title) == key)
        .toList();
    final sameSource = candidates
        .where(
          (t) =>
              t.sourceId.isEmpty ||
              item.sourceId.isEmpty ||
              t.sourceId == item.sourceId,
        )
        .toList();
    if (sameSource.length == 1) return sameSource.single;
    // Re-linking a Plex/WebDAV source changes its id; a single title match in
    // the whole queue is still the same film.
    return candidates.length == 1 ? candidates.single : null;
  }

  bool isCached(MediaItem item) => cachedTaskFor(item) != null;

  bool hasOffline(String itemId) =>
      playableTasks.any((task) => task.itemId == itemId);

  /// Item ids that have a playable file. Matches by id first and then by title,
  /// and checks the file system once per task instead of once per item.
  Set<String> cachedItemIds(Iterable<MediaItem> items) {
    final playable = playableTasks;
    if (playable.isEmpty) return const {};
    final byId = {
      for (final task in playable)
        if (task.itemId.isNotEmpty) task.itemId,
    };
    final byTitle = <String, List<DownloadTask>>{};
    for (final task in playable) {
      byTitle.putIfAbsent(_titleKey(task.title), () => []).add(task);
    }
    final mine = <String>{};
    for (final item in items) {
      if (byId.contains(item.id)) {
        mine.add(item.id);
        continue;
      }
      final key = _titleKey(item.displayTitle);
      if (key.isEmpty) continue;
      final candidates = byTitle[key];
      if (candidates == null) continue;
      final sameSource = candidates.where(
        (t) =>
            t.sourceId.isEmpty ||
            item.sourceId.isEmpty ||
            t.sourceId == item.sourceId,
      );
      if (sameSource.isNotEmpty || candidates.length == 1) mine.add(item.id);
    }
    return mine;
  }

  String? pathFor(String itemId) {
    for (final task in playableTasks.reversed) {
      if (task.itemId == itemId) return task.filePath;
    }
    return null;
  }

  Future<Directory> _configDir() async {
    var dir = directory;
    if (dir == null) {
      final root = '${(await getApplicationSupportDirectory()).path}/SeeWow';
      dir = Directory(root);
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> storageDir() async {
    final explicit = storageDirectory;
    if (explicit != null) return _ensure(explicit);
    final saved = storagePath;
    if (saved != null && saved.trim().isNotEmpty) {
      return _ensure(Directory(saved.trim()));
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      if (home.isNotEmpty) return _ensure(Directory('$home/Movies/SeeWow'));
    }
    final docs = await getApplicationDocumentsDirectory();
    return _ensure(Directory('${docs.path}/SeeWow'));
  }

  Future<Directory> _ensure(Directory dir) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    final file = File('${(await _configDir()).path}/downloads.json');
    if (await file.exists()) {
      try {
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        storagePath = raw['storagePath'] as String?;
        speedLimitKbps = (raw['speedLimitKbps'] as num?)?.toInt() ?? 0;
        tasks
          ..clear()
          ..addAll(
            (raw['tasks'] as List? ?? []).map(
              (e) => DownloadTask.fromJson(e as Map<String, dynamic>),
            ),
          );
        for (final task in tasks) {
          if (task.status == DownloadStatus.downloading) {
            task.status = DownloadStatus.paused;
            task.error = '上次退出时未完成，点继续可续传';
          }
        }
      } catch (error) {
        debugPrint('downloads load failed: $error');
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> save() {
    final payload = jsonEncode({
      'storagePath': storagePath,
      'speedLimitKbps': speedLimitKbps,
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
    final write = _writes.catchError((Object _) {}).then((_) async {
      final dir = await _configDir();
      final temp = File('${dir.path}/downloads.json.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename('${dir.path}/downloads.json');
    });
    _writes = write;
    return write;
  }

  Future<void> setStorageDirectory(String path) async {
    storagePath = path;
    notifyListeners();
    await save();
  }

  Future<void> setSpeedLimit(int kbps) async {
    speedLimitKbps = kbps.clamp(0, 1024 * 1024).toInt();
    notifyListeners();
    await save();
  }

  Future<DownloadTask?> enqueue(
    MediaItem item, {
    MediaSource? source,
    required String sourceName,
    String qualityId = 'original',
  }) async {
    final existing = tasks
        .where((t) => t.itemId == item.id && !t.isFailed)
        .firstOrNull;
    if (existing != null) return existing;
    final quality = qualityById(qualityId);
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      itemId: item.id,
      title: item.displayTitle,
      sourceName: sourceName,
      sourceId: item.sourceId,
      quality: quality.label,
      qualityId: quality.id,
    );
    tasks.add(task);
    notifyListeners();
    await save();
    unawaited(_pump());
    return task;
  }

  Future<void> pause(String id) async {
    _paused.add(id);
    final task = _find(id);
    if (task == null) return;
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.paused;
      task.bytesPerSecond = 0;
      notifyListeners();
      await save();
    }
  }

  Future<void> resume(String id) async {
    final task = _find(id);
    if (task == null) return;
    _paused.remove(id);
    _cancelled.remove(id);
    _samples.remove(id);
    task.status = DownloadStatus.queued;
    task.error = null;
    notifyListeners();
    await save();
    unawaited(_pump());
  }

  Future<void> cancel(String id) async {
    _cancelled.add(id);
    _paused.remove(id);
    final task = _find(id);
    if (task == null) return;
    tasks.remove(task);
    final part = _partFile(task);
    if (part != null && await part.exists()) await part.delete();
    notifyListeners();
    await save();
  }

  Future<void> remove(String id) async {
    final task = _find(id);
    if (task == null) return;
    _cancelled.add(id);
    tasks.remove(task);
    final path = task.filePath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    final part = _partFile(task);
    if (part != null && await part.exists()) await part.delete();
    notifyListeners();
    await save();
  }

  DownloadTask? _find(String id) => tasks.where((t) => t.id == id).firstOrNull;

  File? _partFile(DownloadTask task) {
    final path = task.filePath;
    return path == null ? null : File('$path.part');
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final next = tasks
            .where(
              (t) =>
                  t.status == DownloadStatus.queued &&
                  !_cancelled.contains(t.id),
            )
            .firstOrNull;
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(DownloadTask task) async {
    if (_cancelled.contains(task.id)) return;
    task.status = DownloadStatus.downloading;
    task.error = null;
    task.bytesPerSecond = 0;
    task.updatedAt = DateTime.now();
    notifyListeners();
    IOSink? sink;
    HttpClient? client;
    File? part;
    final limiter = _RateLimiter(speedLimitKbps * 1024);
    try {
      final resolved = await resolver?.call(task.itemId);
      if (resolved == null) throw StateError('片库中找不到该条目，请重新添加');
      final item = _applyQuality(
        resolved.item,
        resolved.source,
        task.qualityId,
      );
      final uri = Uri.tryParse(item.locator);
      if (uri == null || uri.scheme.isEmpty) {
        throw StateError('该条目没有可下载的地址');
      }
      if (uri.path.toLowerCase().endsWith('.m3u8')) {
        await _downloadHls(task, item, uri, limiter);
        return;
      }
      final dir = await storageDir();
      final extension = _extension(uri, item);
      final name = _safeName(item.displayTitle);
      final suffix = task.id.length > 6
          ? task.id.substring(task.id.length - 6)
          : task.id;
      final target = File('${dir.path}/$name [$suffix].$extension');
      task.filePath = target.path;
      part = File('${target.path}.part');

      if (uri.scheme == 'file') {
        final source = File.fromUri(uri);
        if (!await source.exists()) throw StateError('本地文件不存在');
        task.totalBytes = await source.length();
        task.downloadedBytes = 0;
        sink = part.openWrite();
        await for (final chunk in source.openRead()) {
          if (_cancelled.contains(task.id) || _paused.contains(task.id)) {
            break;
          }
          sink.add(chunk);
          task.downloadedBytes += chunk.length;
          _sampleSpeed(task);
          await limiter.wait(chunk.length);
          _progressNotify(task);
        }
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
        final request = await client.getUrl(uri);
        item.httpHeaders.forEach(request.headers.set);
        final existing = await part.exists() ? await part.length() : 0;
        if (existing > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
        }
        final response = await request.close();
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException('服务器返回 HTTP ${response.statusCode}');
        }
        final append = response.statusCode == 206 && existing > 0;
        final start = append ? existing : 0;
        task.downloadedBytes = start;
        task.totalBytes =
            start + (response.contentLength > 0 ? response.contentLength : 0);
        sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
        await for (final chunk in response) {
          if (_cancelled.contains(task.id) || _paused.contains(task.id)) {
            break;
          }
          sink.add(chunk);
          task.downloadedBytes += chunk.length;
          _sampleSpeed(task);
          await limiter.wait(chunk.length);
          _progressNotify(task);
        }
      } else {
        throw StateError('暂不支持该协议：${uri.scheme}');
      }

      await sink.close();
      sink = null;
      if (_cancelled.contains(task.id)) {
        if (part.existsSync()) await part.delete();
        return;
      }
      if (_paused.contains(task.id) || task.status == DownloadStatus.paused) {
        await save();
        return;
      }
      if (task.totalBytes <= 0) task.totalBytes = task.downloadedBytes;
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      task
        ..downloadedBytes = task.totalBytes
        ..status = DownloadStatus.completed
        ..error = null
        ..bytesPerSecond = 0;
    } catch (error) {
      if (!_cancelled.contains(task.id)) {
        task.status = DownloadStatus.failed;
        task.error = _human(error);
        task.bytesPerSecond = 0;
      }
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client?.close(force: true);
      if (_cancelled.contains(task.id) && part != null) {
        try {
          if (await part.exists()) await part.delete();
        } catch (_) {}
      }
      task.updatedAt = DateTime.now();
      notifyListeners();
      await save();
    }
  }

  Future<void> _downloadHls(
    DownloadTask task,
    MediaItem item,
    Uri uri,
    _RateLimiter limiter,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final headers = item.httpHeaders;
      var mediaUri = uri;
      var body = await _fetchText(client, uri, headers);
      final variants = _variants(body, uri);
      if (variants.isNotEmpty) {
        variants.sort((a, b) => a.$2.compareTo(b.$2));
        mediaUri = variants.last.$1;
        body = await _fetchText(client, mediaUri, headers);
      }
      if (RegExp(r'#EXT-X-KEY:(?!METHOD=NONE)').hasMatch(body)) {
        throw StateError('加密 HLS 暂不支持离线缓存');
      }
      if (!body.contains('#EXT-X-ENDLIST')) {
        throw StateError('直播 HLS 暂不支持离线缓存');
      }
      final segments = _segmentUris(body, mediaUri);
      if (segments.isEmpty) throw StateError('HLS 播放列表没有分片');
      final init = _mapUri(body, mediaUri);
      final duration = _durationSeconds(body);
      final quality = qualityById(task.qualityId);
      final kbps = quality.bitrateKbps > 0 ? quality.bitrateKbps : 4000;
      final dir = await storageDir();
      final name = _safeName(item.displayTitle);
      final suffix = task.id.length > 6
          ? task.id.substring(task.id.length - 6)
          : task.id;
      final extension = init == null ? 'ts' : 'mp4';
      final target = File('${dir.path}/$name [$suffix].$extension');
      task.filePath = target.path;
      final part = File('${target.path}.part');
      if (await part.exists()) await part.delete();
      task.downloadedBytes = 0;
      task.totalBytes = duration > 0 ? (duration * kbps * 1000 / 8).round() : 0;
      final sink = part.openWrite();
      try {
        if (init != null) {
          await _appendHttpStream(client, init, headers, sink, task, limiter);
        }
        for (final segment in segments) {
          if (_cancelled.contains(task.id) || _paused.contains(task.id)) {
            break;
          }
          await _appendHttpStream(
            client,
            segment,
            headers,
            sink,
            task,
            limiter,
          );
        }
      } finally {
        await sink.close();
      }
      if (_cancelled.contains(task.id)) {
        if (await part.exists()) await part.delete();
        return;
      }
      if (_paused.contains(task.id) || task.status == DownloadStatus.paused) {
        return;
      }
      task.totalBytes = task.downloadedBytes;
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      task
        ..downloadedBytes = task.totalBytes
        ..status = DownloadStatus.completed
        ..error = null
        ..bytesPerSecond = 0;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _fetchText(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('播放列表返回 HTTP ${response.statusCode}', uri: uri);
    }
    return utf8.decodeStream(response);
  }

  Future<void> _appendHttpStream(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
    IOSink sink,
    DownloadTask task,
    _RateLimiter limiter,
  ) async {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException('HLS 分片返回 HTTP ${response.statusCode}', uri: uri);
    }
    await for (final chunk in response) {
      if (_cancelled.contains(task.id) || _paused.contains(task.id)) break;
      sink.add(chunk);
      task.downloadedBytes += chunk.length;
      _sampleSpeed(task);
      await limiter.wait(chunk.length);
      _progressNotify(task);
    }
  }

  List<(Uri, int)> _variants(String body, Uri base) {
    final lines = const LineSplitter().convert(body);
    final result = <(Uri, int)>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final match = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      var j = i + 1;
      while (j < lines.length &&
          (lines[j].trim().isEmpty || lines[j].trim().startsWith('#'))) {
        j++;
      }
      if (j < lines.length) {
        result.add((
          base.resolve(lines[j].trim()),
          int.tryParse(match?.group(1) ?? '') ?? 0,
        ));
      }
    }
    return result;
  }

  List<Uri> _segmentUris(String body, Uri base) {
    final result = <Uri>[];
    for (final raw in const LineSplitter().convert(body)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final uri = Uri.tryParse(line);
      if (uri != null) result.add(base.resolveUri(uri));
    }
    return result;
  }

  Uri? _mapUri(String body, Uri base) {
    final match = RegExp(r'#EXT-X-MAP:URI="([^"]+)"').firstMatch(body);
    final value = match?.group(1);
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    return uri == null ? null : base.resolveUri(uri);
  }

  double _durationSeconds(String body) {
    var total = 0.0;
    for (final match in RegExp(r'#EXTINF:([0-9.]+)').allMatches(body)) {
      total += double.tryParse(match.group(1) ?? '') ?? 0;
    }
    return total;
  }

  MediaItem _applyQuality(
    MediaItem item,
    MediaSource? source,
    String qualityId,
  ) {
    final locator = buildQualityLocator(item, source, qualityId);
    if (locator == null) return item;
    return item.copyWith(locator: locator);
  }

  void _sampleSpeed(DownloadTask task) {
    final now = DateTime.now();
    final samples = _samples.putIfAbsent(task.id, () => []);
    samples.add((now, task.downloadedBytes));
    samples.removeWhere((sample) => now.difference(sample.$1).inSeconds > 6);
    if (samples.length < 2) return;
    final elapsed = now.difference(samples.first.$1).inMilliseconds;
    if (elapsed < 300) return;
    final bytes = task.downloadedBytes - samples.first.$2;
    if (bytes <= 0) return;
    task.bytesPerSecond = (bytes * 1000 / elapsed).round();
  }

  void _progressNotify(DownloadTask task) {
    final now = DateTime.now();
    final last = _lastNotify[task.id];
    if (last != null && now.difference(last).inMilliseconds < 220) return;
    _lastNotify[task.id] = now;
    task.updatedAt = now;
    notifyListeners();
  }

  String _extension(Uri uri, MediaItem item) {
    final last = uri.path.split('/').last;
    final dot = last.lastIndexOf('.');
    if (dot > 0 && dot < last.length - 1) {
      final ext = last.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) return ext;
    }
    final container = item.container.trim().toLowerCase();
    if (container.isNotEmpty) return container.replaceAll('.', '');
    return 'mp4';
  }

  String _safeName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5 .\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '未命名';
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }

  String _human(Object error) {
    if (error is SocketException) return '网络连接失败，请检查片源是否在线';
    if (error is HttpException) return error.message;
    if (error is FileSystemException) return '写入失败：${error.message}';
    final text = error.toString();
    return text.length > 140 ? text.substring(0, 140) : text;
  }
}

class _RateLimiter {
  _RateLimiter(this.bytesPerSecond);
  final int bytesPerSecond;
  final Stopwatch _clock = Stopwatch()..start();
  int _sent = 0;

  Future<void> wait(int bytes) async {
    if (bytesPerSecond <= 0) return;
    _sent += bytes;
    final expectedMs = _sent * 1000 / bytesPerSecond;
    final delta = expectedMs - _clock.elapsedMilliseconds;
    if (delta > 0) {
      await Future<void>.delayed(Duration(milliseconds: delta.ceil()));
    }
  }
}
