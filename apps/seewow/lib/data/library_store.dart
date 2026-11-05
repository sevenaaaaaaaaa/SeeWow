import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/media_item.dart';

class LibraryStore extends ChangeNotifier {
  final List<MediaItem> items = [];
  final List<MediaSource> sources = [];
  bool scanning = false;
  String? toast;
  Map<String, double> durations = {};

  List<MediaItem> get movies => items.where((i) => i.kind == MediaKind.movie && i.sourceId.isNotEmpty).toList();
  List<MediaItem> get episodes => items.where((i) => i.kind == MediaKind.episode).toList();

  List<MediaItem> get continueWatching {
    final list = items.where((i) => i.position > 30 && !i.watched).toList();
    list.sort((a, b) => b.position.compareTo(a.position));
    return list.take(12).toList();
  }

  List<MediaItem> get recentlyAdded {
    final list = [...items]..sort((a, b) => (b.addedAt ?? DateTime(1970)).compareTo(a.addedAt ?? DateTime(1970)));
    return list.take(20).toList();
  }

  List<MediaItem> get series {
    final map = <String, MediaItem>{};
    for (final e in episodes) {
      map.putIfAbsent(e.showTitle ?? e.title, () => e);
    }
    return map.values.toList();
  }

  Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final d = Directory('${support.path}/SeeWow');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    final d = await _dir();
    final file = File('${d.path}/library.json');
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      items
        ..clear()
        ..addAll((raw['items'] as List).map((e) => MediaItem.fromJson(e as Map<String, dynamic>)));
      sources
        ..clear()
        ..addAll((raw['sources'] as List).map((e) => MediaSource.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (e) {
      debugPrint('library load failed: $e');
    }
  }

  Future<void> save() async {
    final d = await _dir();
    final payload = jsonEncode({
      'items': items.map((e) => e.toJson()).toList(),
      'sources': sources.map((e) => e.toJson()).toList(),
    });
    await File('${d.path}/library.json').writeAsString(payload);
  }

  Future<void> addSource(MediaSource source) async {
    sources.removeWhere((s) => s.location == source.location);
    sources.add(source);
    await save();
    await rescan(source);
  }

  Future<void> removeSource(MediaSource source) async {
    sources.removeWhere((s) => s.id == source.id);
    items.removeWhere((i) => i.sourceId == source.id);
    await save();
    notifyListeners();
  }

  Future<void> rescan(MediaSource source) async {
    scanning = true;
    notifyListeners();
    try {
      final scanned = await _scan(source);
      final old = {for (final i in items.where((i) => i.sourceId == source.id)) i.locator: i};
      final merged = scanned.map((n) {
        final prev = old[n.locator];
        if (prev == null) return n;
        return n.copyWith(position: prev.position, duration: prev.duration > 0 ? prev.duration : null, isFavorite: prev.isFavorite);
      }).toList();
      items.removeWhere((i) => i.sourceId == source.id);
      items.addAll(merged);
      await save();
    } catch (e) {
      toast = '扫描失败：$e';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<List<MediaItem>> _scan(MediaSource source) async {
    // Injected by the app so the store stays testable.
    if (scanner == null) return [];
    return scanner!(source);
  }

  Future<List<MediaItem>> Function(MediaSource source)? scanner;

  void updatePosition(MediaItem item, double position, double duration) {
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx < 0) return;
    items[idx] = items[idx].copyWith(position: position, duration: duration);
    save();
    notifyListeners();
  }

  void showToast(String text) {
    toast = text;
    notifyListeners();
    Future.delayed(const Duration(seconds: 3), () {
      if (toast == text) {
        toast = null;
        notifyListeners();
      }
    });
  }
}
