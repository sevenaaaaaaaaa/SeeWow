import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';
import '../metadata/cover_generator.dart';

class FrameBookmark {
  const FrameBookmark({
    required this.id,
    required this.itemId,
    required this.title,
    required this.seconds,
    required this.createdAt,
    this.note = '',
  });
  final String id, itemId, title, note;
  final double seconds;
  final DateTime createdAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'title': title,
    'seconds': seconds,
    'createdAt': createdAt.toIso8601String(),
    'note': note,
  };
  factory FrameBookmark.fromJson(Map<String, dynamic> j) => FrameBookmark(
    id: j['id'] as String,
    itemId: j['itemId'] as String,
    title: j['title'] as String,
    seconds: (j['seconds'] as num).toDouble(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    note: j['note'] as String? ?? '',
  );
}

class FrameBookmarks {
  FrameBookmarks({this.directory});
  static final I = FrameBookmarks();
  final Directory? directory;
  static Future<void> validateImage(Uint8List bytes) async {
    if (bytes.length > 8 * 1024 * 1024)
      throw const FormatException('画面超过 8 MiB，请选择较低分辨率画面');
    await validateCoverBytes(bytes);
  }

  Future<void> _writes = Future.value();
  Future<Directory> _dir() async {
    final dir =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/SeeWow/frames',
        );
    await dir.create(recursive: true);
    return dir;
  }

  bool _validId(String id) => RegExp(r'^[a-f0-9]{64}$').hasMatch(id);
  Future<List<FrameBookmark>> list({String? itemId}) async {
    await _writes.catchError((Object _) {});
    final all = await _read();
    return all.where((f) => itemId == null || f.itemId == itemId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<FrameBookmark>> _read() async {
    final file = File('${(await _dir()).path}/index.json');
    if (!await file.exists()) return [];
    if (await file.length() > 4 * 1024 * 1024)
      throw const FormatException('精彩帧索引过大');
    final values = (jsonDecode(await file.readAsString()) as List)
        .map((j) => FrameBookmark.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    if (values.any(
      (f) => !_validId(f.id) || !f.seconds.isFinite || f.seconds < 0,
    ))
      throw const FormatException('精彩帧索引格式无效');
    return values;
  }

  Future<String> path(FrameBookmark frame) async {
    if (!_validId(frame.id)) throw const FormatException('精彩帧标识无效');
    return '${(await _dir()).path}/${frame.id}.jpg';
  }

  Future<void> _save(List<FrameBookmark> frames) async {
    final dir = await _dir(),
        data = jsonEncode(frames.map((f) => f.toJson()).toList());
    if (utf8.encode(data).length > 4 * 1024 * 1024)
      throw const FormatException('收藏数量已达到索引容量');
    final temp = File('${dir.path}/index.json.tmp');
    await temp.writeAsString(data, flush: true);
    await temp.rename('${dir.path}/index.json');
  }

  Future<FrameBookmark> add(
    MediaItem item,
    double seconds,
    Uint8List bytes, {
    String note = '',
  }) {
    final done = _writes.catchError((Object _) {}).then((_) async {
      if (!seconds.isFinite || seconds < 0 || note.length > 2000)
        throw const FormatException('收藏时间或备注无效');
      await validateImage(bytes);
      final now = DateTime.now().toUtc();
      final id = sha256
          .convert(
            utf8.encode('${item.id}:$seconds:${now.microsecondsSinceEpoch}'),
          )
          .toString();
      final frame = FrameBookmark(
        id: id,
        itemId: item.id,
        title: item.displayTitle,
        seconds: seconds,
        createdAt: now,
        note: note.trim(),
      );
      final all = await _read();
      final file = File(await path(frame));
      try {
        await file.writeAsBytes(bytes, flush: true);
        await _save([...all, frame]);
      } catch (_) {
        if (await file.exists()) await file.delete();
        rethrow;
      }
      return frame;
    });
    _writes = done.then((_) {}).catchError((Object _) {});
    return done;
  }

  Future<void> remove(FrameBookmark frame) {
    final done = _writes.catchError((Object _) {}).then((_) async {
      final all = await _read();
      await _save(all.where((f) => f.id != frame.id).toList());
      final file = File(await path(frame));
      if (await file.exists()) await file.delete();
    });
    _writes = done;
    return done;
  }
}
