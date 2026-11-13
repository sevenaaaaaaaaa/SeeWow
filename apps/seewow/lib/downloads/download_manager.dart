import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';
import 'download_task.dart';

typedef DownloadItemResolver = Future<MediaItem?> Function(String itemId);

class DownloadManager extends ChangeNotifier {
  DownloadManager({this.directory, this.storageDirectory, this.resolver});

  final Directory? directory;
  final Directory? storageDirectory;
  DownloadItemResolver? resolver;
  final List<DownloadTask> tasks = [];
  String? storagePath;
  bool loaded = false;

  Future<void> _writes = Future.value();
  bool _pumping = false;
  final Set<String> _paused = {};
  final Set<String> _cancelled = {};
  final Map<String, DateTime> _lastNotify = {};

  int get activeCount => tasks.where((t) => t.isActive).length;
  int get completedCount => tasks.where((t) => t.isDone).length;
  int get offlineBytes =>
      tasks.where((t) => t.isDone).fold(0, (sum, t) => sum + t.totalBytes);

  DownloadTask? taskFor(String itemId) =>
      tasks.where((t) => t.itemId == itemId).firstOrNull;

  bool hasOffline(String itemId) {
    final task = taskFor(itemId);
    if (task == null || !task.isDone) return false;
    final path = task.filePath;
    return path != null && File(path).existsSync();
  }

  String? pathFor(String itemId) {
    final task = taskFor(itemId);
    final path = task?.filePath;
    if (task == null || !task.isDone || path == null) return null;
    return File(path).existsSync() ? path : null;
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

  Future<DownloadTask?> enqueue(
    MediaItem item, {
    required String sourceName,
  }) async {
    final existing = tasks
        .where((t) => t.itemId == item.id && !t.isFailed)
        .firstOrNull;
    if (existing != null) return existing;
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      itemId: item.id,
      title: item.displayTitle,
      sourceName: sourceName,
      sourceId: item.sourceId,
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
      notifyListeners();
      await save();
    }
  }

  Future<void> resume(String id) async {
    final task = _find(id);
    if (task == null) return;
    _paused.remove(id);
    _cancelled.remove(id);
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
    notifyListeners();
    IOSink? sink;
    HttpClient? client;
    File? part;
    try {
      final item = await resolver?.call(task.itemId);
      if (item == null) throw StateError('片库中找不到该条目，请重新添加');
      final uri = Uri.tryParse(item.locator);
      if (uri == null || uri.scheme.isEmpty) {
        throw StateError('该条目没有可下载的地址');
      }
      if (uri.path.toLowerCase().endsWith('.m3u8') ||
          item.locator.toLowerCase().contains('.m3u8')) {
        throw StateError('HLS / 转码流暂不支持离线缓存，请选择直连片源');
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
        ..error = null;
    } catch (error) {
      if (!_cancelled.contains(task.id)) {
        task.status = DownloadStatus.failed;
        task.error = _human(error);
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
