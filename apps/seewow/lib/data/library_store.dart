import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import '../domain/metadata_language_draft.dart';
import '../domain/library_intelligence.dart';
import '../metadata/cover_generator.dart';

class LibraryStore extends ChangeNotifier {
  LibraryStore({this.directory});
  final Directory? directory;
  final List<MediaItem> items = [];
  final List<MediaSource> sources = [];
  final List<FilmCollection> collections = [];
  final TasteProfile taste = TasteProfile();
  final Map<String, String> sourceErrors = {};
  final Set<String> scanningIds = {};
  bool get scanning => scanningIds.isNotEmpty;
  String? toast;
  Future<void> _writes = Future.value();
  final Map<String, Future<void>> _scans = {};

  List<MediaItem> get movies => items
      .where((i) => i.kind == MediaKind.movie && i.sourceId.isNotEmpty)
      .toList();
  List<MediaItem> get episodes =>
      items.where((i) => i.kind == MediaKind.episode).toList();
  List<MediaItem> get continueWatching {
    final list = items.where((i) => i.position > 30 && !i.watched).toList();
    list.sort(
      (a, b) => (taste.lastPlayed[b.id] ?? DateTime(1970)).compareTo(
        taste.lastPlayed[a.id] ?? DateTime(1970),
      ),
    );
    return list.take(12).toList();
  }

  List<MediaItem> get recentlyAdded =>
      const LibraryQuery().apply(items, taste).take(20).toList();
  List<MediaItem> get series {
    final map = <String, MediaItem>{};
    for (final e in episodes) {
      map.putIfAbsent(e.showTitle ?? e.title, () => e);
    }
    return map.values.toList();
  }

  List<FilmPick> recommendations({String prompt = '', int limit = 12}) =>
      RecommendationEngine().recommend(
        items,
        taste,
        prompt: prompt,
        limit: limit,
      );
  MediaItem current(MediaItem item) =>
      items.where((i) => i.id == item.id).firstOrNull ?? item;
  Future<Directory> _dir() async {
    final d =
        directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/SeeWow');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    final file = File('${(await _dir()).path}/library.json');
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      items
        ..clear()
        ..addAll(
          (raw['items'] as List? ?? []).map(
            (e) => MediaItem.fromJson(e as Map<String, dynamic>),
          ),
        );
      sources
        ..clear()
        ..addAll(
          (raw['sources'] as List? ?? []).map(
            (e) => MediaSource.fromJson(e as Map<String, dynamic>),
          ),
        );
      collections
        ..clear()
        ..addAll(
          (raw['collections'] as List? ?? []).map(
            (e) => FilmCollection.fromJson(e as Map<String, dynamic>),
          ),
        );
      taste.read(raw['taste'] as Map<String, dynamic>? ?? {});
      sourceErrors
        ..clear()
        ..addAll(
          (raw['sourceErrors'] as Map<String, dynamic>? ?? {})
              .cast<String, String>(),
        );
      notifyListeners();
    } catch (e) {
      debugPrint('library load failed: $e');
    }
  }

  Future<void> save() {
    final payload = jsonEncode({
      'items': items.map((e) => e.toJson()).toList(),
      'sources': sources.map((e) => e.toJson()).toList(),
      'collections': collections.map((e) => e.toJson()).toList(),
      'taste': taste.toJson(),
      'sourceErrors': sourceErrors,
    });
    final write = _writes.catchError((Object _) {}).then((_) async {
      final d = await _dir();
      final temp = File('${d.path}/library.json.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename('${d.path}/library.json');
    });
    _writes = write;
    return write;
  }

  Future<void> addSource(MediaSource source) async {
    final existing = sources
        .where(
          (s) =>
              s.location == source.location &&
              s.rootPath == source.rootPath &&
              s.kind == source.kind,
        )
        .firstOrNull;
    if (existing != null) {
      await rescan(existing);
      return;
    }
    sources.add(source);
    await save();
    notifyListeners();
    await rescan(source);
  }

  Future<void> updateSource(MediaSource source) async {
    await _scans[source.id];
    final index = sources.indexWhere((s) => s.id == source.id);
    if (index < 0) throw StateError('来源已移除');
    if (sources.any(
      (s) =>
          s.id != source.id &&
          s.location == source.location &&
          s.rootPath == source.rootPath,
    ))
      throw StateError('此连接与目录已存在');
    sources[index] = source;
    await save();
    notifyListeners();
    await rescan(source);
  }

  Future<void> removeSource(MediaSource source) async {
    // Wait for a running scan so it cannot resurrect removed items.
    await _scans[source.id];
    sources.removeWhere((s) => s.id == source.id);
    items.removeWhere((i) => i.sourceId == source.id);
    sourceErrors.remove(source.id);
    await save();
    notifyListeners();
  }

  Future<void> rescan(MediaSource source) {
    if (_scans.containsKey(source.id)) return _scans[source.id]!;
    final future = _rescan(source);
    _scans[source.id] = future;
    return future.whenComplete(() => _scans.remove(source.id));
  }

  Future<void> _rescan(MediaSource source) async {
    scanningIds.add(source.id);
    sourceErrors.remove(source.id);
    notifyListeners();
    try {
      if (scanner == null) throw StateError('扫描器尚未就绪');
      final scanned = await scanner!(source);
      final old = {
        for (final i in items.where((i) => i.sourceId == source.id))
          i.locator: i,
      };
      final oldById = {for (final item in old.values) item.id: item};
      final seriesMetadata = {
        for (final previous in old.values)
          if (previous.kind == MediaKind.episode &&
              previous.metadata?.reviewed == true &&
              previous.metadata?.mediaType == 'tv')
            previous.showTitle ?? previous.title: previous.metadata!,
      };
      final merged = scanned.map((n) {
        final prev = old[n.locator] ?? oldById[n.id];
        final match =
            (prev?.metadata?.reviewed == true ? prev?.metadata : null) ??
            (n.kind == MediaKind.episode
                ? seriesMetadata[n.showTitle ?? n.title]
                : null);
        var incoming = match == null ? n : n.withMetadata(match);
        if (prev?.hasGeneratedCover == true &&
            (incoming.posterUrl == null || incoming.posterUrl!.isEmpty)) {
          incoming = incoming.copyWith(
            posterUrl: prev!.posterUrl,
            metadata: MediaMetadata.fromJson({
              ...metadataForLanguages(incoming).toJson(),
              'posterUrl': prev.posterUrl,
              'generatedCover': prev.metadata!.generatedCover,
            }),
          );
        }
        if (prev?.metadata?.localized.isNotEmpty == true)
          incoming = incoming.copyWith(
            metadata: retainLanguages(
              metadataForLanguages(incoming),
              prev!.metadata,
            ),
          );
        return prev == null
            ? incoming
            : incoming.copyWith(
                position: prev.position,
                duration: prev.duration > 0 ? prev.duration : null,
                isFavorite: prev.isFavorite,
              );
      }).toList();
      items.removeWhere((i) => i.sourceId == source.id);
      items.addAll(merged);
      final index = sources.indexWhere((s) => s.id == source.id);
      if (index >= 0)
        sources[index] = MediaSource(
          id: source.id,
          kind: source.kind,
          name: source.name,
          location: source.location,
          username: source.username,
          enabled: source.enabled,
          lastScan: DateTime.now(),
          providerId: source.providerId,
          rootPath: source.rootPath,
        );
    } catch (e) {
      // Preserve the previous library when a source is offline.
      sourceErrors[source.id] = e.toString();
      toast = '${source.name}：扫描失败，已保留原有条目';
    } finally {
      scanningIds.remove(source.id);
      await save();
      notifyListeners();
    }
  }

  Future<List<MediaItem>> Function(MediaSource source)? scanner;
  Future<void> updatePosition(
    MediaItem item,
    double position,
    double duration,
  ) async {
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx < 0) return;
    items[idx] = items[idx].copyWith(position: position, duration: duration);
    taste.lastPlayed[item.id] = DateTime.now();
    await save();
    notifyListeners();
  }

  Future<void> hydrateCredentials(
    Future<Map<String, String>> Function(MediaSource) headersFor,
  ) async {
    for (final source in sources) {
      try {
        final headers = await headersFor(source);
        for (var n = 0; n < items.length; n++) {
          if (items[n].sourceId == source.id)
            items[n] = items[n].copyWith(
              httpHeaders: {...items[n].httpHeaders.wherePublic(), ...headers},
            );
        }
      } catch (_) {
        sourceErrors[source.id] = '凭据读取失败，请重新连接片源';
      }
    }
    notifyListeners();
  }

  Future<void> applyMetadata(String itemId, MediaMetadata match) async {
    final index = items.indexWhere((i) => i.id == itemId);
    if (index < 0) throw StateError('此条目已移出片库，请刷新后重试');
    final item = items[index];
    if (match.provider == 'tmdb' &&
        (item.kind == MediaKind.movie && match.mediaType != 'movie' ||
            item.kind == MediaKind.episode &&
                !['tv', 'episode'].contains(match.mediaType) ||
            item.kind == MediaKind.audio ||
            item.kind == MediaKind.other)) {
      throw const FormatException('元数据类型与媒体条目不一致');
    }
    if (item.kind == MediaKind.episode && match.mediaType == 'tv') {
      final show = item.showTitle ?? item.title;
      for (var n = 0; n < items.length; n++) {
        final episode = items[n];
        if (episode.kind == MediaKind.episode &&
            episode.sourceId == item.sourceId &&
            (episode.showTitle ?? episode.title) == show)
          items[n] = episode.withMetadata(
            retainLanguages(match, episode.metadata),
          );
      }
    } else {
      items[index] = item.withMetadata(retainLanguages(match, item.metadata));
    }
    await _changed();
  }

  Future<void> applyLanguageDrafts(List<MetadataLanguageDraft> drafts) async {
    final previous = <String, MediaMetadata?>{};
    final next = <String, MediaMetadata>{};
    for (final draft in drafts) {
      final item = items.where((i) => i.id == draft.itemId).firstOrNull;
      if (item == null || metadataSnapshot(item) != draft.before)
        throw const FormatException('资料或来源已改变，请重新生成多语言预览');
      if (draft.generatedByModel && !item.aiAllowed)
        throw const FormatException('此来源不允许 AI 处理');
      final base = metadataForLanguages(item);
      for (final entry in draft.metadata.localized.entries) {
        final old = base.localized[entry.key];
        if (old == null) continue;
        final value = entry.value;
        if ((old.title.isNotEmpty &&
                old.titleOrigin != 'machine' &&
                value.titleOrigin == 'machine' &&
                value.title != old.title) ||
            (old.overview.isNotEmpty &&
                old.overviewOrigin != 'machine' &&
                value.overviewOrigin == 'machine' &&
                value.overview != old.overview))
          throw const FormatException('本机补译不能覆盖已有来源文字');
      }
      previous[item.id] = item.metadata;
      next[item.id] = base.withLanguages(
        draft.metadata.localized,
        alternatives: draft.metadata.alternativeTitles,
        preferred: draft.metadata.preferredLanguages,
      );
    }
    for (var i = 0; i < items.length; i++) {
      final metadata = next[items[i].id];
      if (metadata != null) items[i] = items[i].copyWith(metadata: metadata);
    }
    try {
      await _changed();
    } catch (_) {
      for (var i = 0; i < items.length; i++) {
        if (previous.containsKey(items[i].id))
          items[i] = items[i].copyWith(
            metadata: previous[items[i].id],
            clearMetadata: previous[items[i].id] == null,
          );
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> applyGeneratedCover({
    required String itemId,
    required String before,
    required Uint8List bytes,
    required String model,
    required DateTime createdAt,
    bool replace = false,
  }) async {
    void validateCurrent() {
      final item = items.where((i) => i.id == itemId).firstOrNull;
      if (item == null || metadataSnapshot(item) != before)
        throw const FormatException('媒体资料或封面已改变，请重新生成预览');
      if (!item.aiAllowed) throw const FormatException('此来源不允许 AI 处理');
      if (!replace &&
          item.posterUrl?.isNotEmpty == true &&
          !item.posterUrl!.startsWith('seewow:'))
        throw const FormatException('此条目已有封面，请明确选择替换');
    }

    validateCurrent();
    await validateCoverBytes(bytes);
    final dir = Directory('${(await _dir()).path}/covers');
    await dir.create(recursive: true);
    final name = sha256.convert(
      utf8.encode(
        '$itemId:${DateTime.now().microsecondsSinceEpoch}:${sha256.convert(bytes)}',
      ),
    );
    final file = File('${dir.path}/$name.image');
    try {
      await file.writeAsBytes(bytes, flush: true);
      validateCurrent();
      final index = items.indexWhere((i) => i.id == itemId);
      final item = items[index];
      final oldMetadata = item.metadata;
      final base = metadataForLanguages(item);
      items[index] = item.copyWith(
        posterUrl: file.path,
        metadata: MediaMetadata.fromJson({
          ...base.toJson(),
          'posterUrl': file.path,
          'generatedCover': {
            'path': file.path,
            'model': model,
            'createdAt': createdAt.toIso8601String(),
          },
        }),
      );
      final appliedMetadata = items[index].metadata;
      try {
        await _changed();
      } catch (_) {
        final currentIndex = items.indexWhere((i) => i.id == itemId);
        if (currentIndex >= 0 &&
            items[currentIndex].posterUrl == file.path &&
            identical(items[currentIndex].metadata, appliedMetadata)) {
          final current = items[currentIndex];
          items[currentIndex] = MediaItem.fromJson({
            ...current.toJson(),
            'locator': current.locator,
            'posterUrl': item.posterUrl,
            'metadata': oldMetadata?.toJson(),
          }).copyWith(httpHeaders: current.httpHeaders);
        }
        notifyListeners();
        rethrow;
      }
    } catch (_) {
      final referenced = items.any(
        (i) =>
            i.posterUrl == file.path ||
            i.backdropUrl == file.path ||
            i.metadata?.posterUrl == file.path,
      );
      if (!referenced && await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> setFavorite(MediaItem item, bool value) async {
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx < 0) return;
    items[idx] = items[idx].copyWith(isFavorite: value);
    if (value) taste.dislikedIds.remove(item.id);
    await _changed();
  }

  Future<void> toggleWatchlist(MediaItem item) async {
    if (!taste.watchlist.remove(item.id)) taste.watchlist.add(item.id);
    await _changed();
  }

  Future<void> setDisliked(MediaItem item, bool value) async {
    if (value) {
      taste.dislikedIds.add(item.id);
    } else {
      taste.dislikedIds.remove(item.id);
    }
    await _changed();
  }

  Future<void> toggleGenre(String genre) async {
    if (!taste.genres.remove(genre)) taste.genres.add(genre);
    await _changed();
  }

  Future<void> markWatched(Iterable<MediaItem> selected, bool value) async {
    final ids = selected.map((i) => i.id).toSet();
    for (var n = 0; n < items.length; n++) {
      final item = items[n];
      if (ids.contains(item.id))
        items[n] = item.copyWith(
          duration: value && item.duration <= 0 ? 1 : item.duration,
          position: value ? (item.duration > 0 ? item.duration : 1) : 0,
        );
    }
    await _changed();
  }

  Future<FilmCollection> createCollection(
    String name,
    Iterable<String> ids, {
    String description = '',
  }) async {
    final valid = items.map((i) => i.id).toSet();
    final collection = FilmCollection(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? '我的片单' : name.trim(),
      itemIds: ids.where(valid.contains).toSet().toList(),
      createdAt: DateTime.now(),
      description: description,
    );
    collections.insert(0, collection);
    await _changed();
    return collection;
  }

  Future<void> removeCollection(String id) async {
    collections.removeWhere((c) => c.id == id);
    await _changed();
  }

  Future<void> _changed() async {
    notifyListeners();
    await save();
  }

  void showToast(String text) {
    toast = text;
    notifyListeners();
  }
}
