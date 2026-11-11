import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/iptv.dart';
import '../domain/xmltv.dart';
import '../domain/subscription.dart';
import '../sources/subscription_reader.dart';

/// A channel that is on air right now, used by the "正在播" rail.
class NowOnAir {
  NowOnAir(this.channel, this.program);
  final IPTVChannel channel;
  final EPGProgram program;
}

/// IPTV playlists, channels, EPG and favourites, persisted next to the
/// movie library as plain JSON.
class IPTVStore extends ChangeNotifier {
  IPTVStore({this.directory, this.reader = const SubscriptionReader()});
  final Directory? directory;
  final SubscriptionReader reader;
  Future<void> _writes = Future.value();
  final List<IPTVPlaylist> playlists = [];
  final List<IPTVChannel> channels = [];
  final Map<String, List<EPGProgram>> epg = {};
  final List<String> favorites = [];
  final List<String> recents = [];
  bool loading = false;
  String? toast;

  List<String> get groups {
    final seen = <String>[];
    for (final c in channels) {
      if (!seen.contains(c.group)) seen.add(c.group);
    }
    return seen;
  }

  bool get hasEpg => epg.isNotEmpty;

  Future<Directory> _dir() async {
    final d =
        directory ??
        Directory('${(await getApplicationSupportDirectory()).path}/SeeWow');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    final d = await _dir();
    final file = File(d.path + '/iptv.json');
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      playlists
        ..clear()
        ..addAll(
          (raw['playlists'] as List? ?? []).map(
            (e) => IPTVPlaylist.fromJson(e as Map<String, dynamic>),
          ),
        );
      channels
        ..clear()
        ..addAll(
          (raw['channels'] as List? ?? []).map(
            (e) => IPTVChannel.fromJson(e as Map<String, dynamic>),
          ),
        );
      epg.clear();
      final rawEpg = raw['epg'] as Map<String, dynamic>? ?? {};
      rawEpg.forEach((key, value) {
        epg[key] = (value as List)
            .map((e) => EPGProgram.fromJson(e as Map<String, dynamic>))
            .toList();
      });
      favorites
        ..clear()
        ..addAll((raw['favorites'] as List? ?? []).map((e) => e as String));
      recents
        ..clear()
        ..addAll((raw['recents'] as List? ?? []).map((e) => e as String));
      for (final playlist in playlists) {
        for (final channelId in _epgChannelIds(playlist)) {
          if (epg.containsKey(channelId))
            epg.putIfAbsent(
              '${playlist.id}::$channelId',
              () => epg[channelId]!,
            );
        }
      }
      epg.removeWhere((key, _) => !key.contains('::'));
      _pruneEpg();
      notifyListeners();
    } catch (e) {
      debugPrint('iptv load failed: ' + e.toString());
    }
  }

  Future<void> save() async {
    final payload = jsonEncode({
      'playlists': playlists.map((e) => e.toJson()).toList(),
      'channels': channels.map((e) => e.toJson()).toList(),
      'epg': epg.map(
        (key, value) => MapEntry(key, value.map((e) => e.toJson()).toList()),
      ),
      'favorites': favorites,
      'recents': recents,
    });
    final write = _writes.catchError((Object _) {}).then((_) async {
      final d = await _dir();
      final temp = File('${d.path}/iptv.json.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename('${d.path}/iptv.json');
    });
    _writes = write;
    await write;
  }

  Future<SubscriptionPreview> preview(
    String source, {
    bool allowLocalNetwork = false,
  }) async {
    final document = await reader.read(
      source,
      allowLocalNetwork: allowLocalNetwork,
    );
    return SubscriptionParser.parse(
      document.text,
      uri: document.uri,
      playlistId: 'preview',
    );
  }

  Future<bool> addPlaylist({
    required String name,
    required String source,
    String? epgUrl,
    bool allowLocalNetwork = false,
  }) async {
    try {
      final data = await preview(source, allowLocalNetwork: allowLocalNetwork);
      return await importPreview(
        data,
        name: name,
        source: source,
        epgUrl: epgUrl,
        allowLocalNetwork: allowLocalNetwork,
      );
    } catch (_) {
      toast = '读取失败，请检查地址、文件格式和访问权限';
      notifyListeners();
      return false;
    }
  }

  /// Commits the exact preview confirmed by the user; never fetches child configs.
  Future<bool> importPreview(
    SubscriptionPreview data, {
    required String name,
    String? source,
    String? epgUrl,
    bool allowLocalNetwork = false,
  }) async {
    if (loading) return false;
    loading = true;
    toast = null;
    notifyListeners();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      if (data.channels.isEmpty) throw const FormatException('请先选择含频道列表的配置');
      final selectedEpg = epgUrl == null
          ? data.epgUrl
          : epgUrl.trim().isEmpty
          ? null
          : epgUrl.trim();
      if (selectedEpg != null)
        SubscriptionReader.validateWebUri(Uri.parse(selectedEpg));
      final parsed = M3UParser.stableIds(data.channels, id);
      var playlist = IPTVPlaylist(
        id: id,
        name: name.trim().isEmpty
            ? _nameFrom(data.uri.toString())
            : name.trim(),
        source: source ?? data.uri.toString(),
        channelCount: parsed.length,
        updatedAt: DateTime.now(),
        epgUrl: selectedEpg,
        allowLocalNetwork: allowLocalNetwork,
      );
      final guide = await _loadEpg(
        selectedEpg,
        allowLocalNetwork: allowLocalNetwork,
      );
      if (guide != null) {
        epg.addAll(guide.map((key, value) => MapEntry('$id::$key', value)));
        playlist = playlist.copyWith(
          epgCount: guide.values.fold<int>(0, (sum, list) => sum + list.length),
        );
      }
      channels.addAll(parsed);
      playlists.add(playlist);
      await save();
      toast =
          '已添加 ${parsed.length} 个频道${selectedEpg != null && guide == null ? '，节目单暂未加载，可稍后重试' : ''}';
      return true;
    } catch (_) {
      epg.removeWhere((key, _) => key.startsWith('$id::'));
      channels.removeWhere((c) => c.playlistId == id);
      playlists.removeWhere((p) => p.id == id);
      toast = '导入失败，请检查频道和节目单地址，或先选择下级配置';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reload(IPTVPlaylist playlist) async {
    if (loading) return;
    final oldChannels = List<IPTVChannel>.of(channels);
    final oldPlaylists = List<IPTVPlaylist>.of(playlists);
    final oldFavorites = List<String>.of(favorites),
        oldRecents = List<String>.of(recents);
    loading = true;
    notifyListeners();
    try {
      final data = await preview(
        playlist.source,
        allowLocalNetwork: playlist.allowLocalNetwork,
      );
      if (data.channels.isEmpty)
        throw const FormatException('订阅已变为配置目录或没有频道，保留原列表');
      if (!playlists.any((p) => p.id == playlist.id)) return;
      final parsed = M3UParser.stableIds(data.channels, playlist.id);
      // Migrate the previous index-based IDs without moving favourites.
      final old = channels.where((c) => c.playlistId == playlist.id).toList();
      for (final channel in old) {
        final replacement = parsed
            .where((c) => c.url == channel.url && c.name == channel.name)
            .firstOrNull;
        if (replacement == null) continue;
        for (final ids in [favorites, recents]) {
          for (var i = 0; i < ids.length; i++) {
            if (ids[i] == channel.id) ids[i] = replacement.id;
          }
        }
      }
      channels.removeWhere((c) => c.playlistId == playlist.id);
      channels.addAll(parsed);
      final idx = playlists.indexWhere((p) => p.id == playlist.id);
      if (idx >= 0) {
        playlists[idx] = playlist.copyWith(
          channelCount: parsed.length,
          updatedAt: DateTime.now(),
        );
      }
      await save();
      toast = '已更新 ' + parsed.length.toString() + ' 个频道';
      if (playlist.epgUrl != null) await refreshEpg(playlist);
    } catch (e) {
      channels
        ..clear()
        ..addAll(oldChannels);
      playlists
        ..clear()
        ..addAll(oldPlaylists);
      favorites
        ..clear()
        ..addAll(oldFavorites);
      recents
        ..clear()
        ..addAll(oldRecents);
      toast = '更新失败，已保留上次频道。请检查订阅格式、网络和访问权限';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshEpg(IPTVPlaylist playlist) async {
    final url = playlist.epgUrl;
    if (url == null || url.isEmpty) {
      toast = '这个列表还没有节目单地址';
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final guide = await _loadEpg(
        url,
        allowLocalNetwork: playlist.allowLocalNetwork,
      );
      if (guide == null) throw StateError('节目单为空');
      final oldIds = epg.keys
          .where((k) => k.startsWith('${playlist.id}::'))
          .toList();
      for (final id in oldIds) {
        epg.remove(id);
      }
      epg.addAll(
        guide.map((key, value) => MapEntry('${playlist.id}::$key', value)),
      );
      final count = guide.values.fold<int>(0, (sum, list) => sum + list.length);
      final idx = playlists.indexWhere((p) => p.id == playlist.id);
      if (idx >= 0) playlists[idx] = playlists[idx].copyWith(epgCount: count);
      await save();
      toast = '节目单已更新：' + count.toString() + ' 条';
    } catch (e) {
      toast = '节目单更新失败，请检查地址和 XMLTV 格式';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> setEpgUrl(IPTVPlaylist playlist, String url) async {
    final idx = playlists.indexWhere((p) => p.id == playlist.id);
    if (idx < 0) return false;
    final value = url.trim();
    if (value.isNotEmpty) {
      try {
        SubscriptionReader.validateWebUri(Uri.parse(value));
      } catch (_) {
        toast = '节目单需要有效的 HTTP(S) 地址';
        notifyListeners();
        return false;
      }
    }
    playlists[idx] = playlists[idx].copyWith(
      epgUrl: value,
      clearEpg: value.isEmpty,
      epgCount: value.isEmpty ? 0 : null,
    );
    if (value.isEmpty)
      epg.removeWhere((key, _) => key.startsWith('${playlist.id}::'));
    await save();
    notifyListeners();
    if (value.isNotEmpty) await refreshEpg(playlists[idx]);
    return true;
  }

  Future<void> removePlaylist(IPTVPlaylist playlist) async {
    if (loading) return;
    playlists.removeWhere((p) => p.id == playlist.id);
    epg.removeWhere((key, _) => key.startsWith('${playlist.id}::'));
    final removed = channels.where((c) => c.playlistId == playlist.id).toList();
    channels.removeWhere((c) => c.playlistId == playlist.id);
    favorites.removeWhere((id) => removed.any((c) => c.id == id));
    recents.removeWhere((id) => removed.any((c) => c.id == id));
    await save();
    notifyListeners();
  }

  List<IPTVChannel> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return channels;
    return channels
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.group.toLowerCase().contains(q),
        )
        .toList();
  }

  // ---------------------------------------------------------------- favourites

  bool isFavorite(IPTVChannel channel) => favorites.contains(channel.id);

  Future<void> toggleFavorite(IPTVChannel channel) async {
    if (!favorites.remove(channel.id)) favorites.add(channel.id);
    await save();
    notifyListeners();
  }

  List<IPTVChannel> get favoriteChannels =>
      channels.where((c) => favorites.contains(c.id)).toList();

  // ------------------------------------------------------------------- recents

  Future<void> markWatched(IPTVChannel channel) async {
    recents.remove(channel.id);
    recents.insert(0, channel.id);
    if (recents.length > 10) recents.removeRange(10, recents.length);
    await save();
    notifyListeners();
  }

  List<IPTVChannel> get recentChannels {
    final out = <IPTVChannel>[];
    for (final id in recents) {
      final match = channels.where((c) => c.id == id);
      if (match.isNotEmpty) out.add(match.first);
    }
    return out;
  }

  // ----------------------------------------------------------------------- EPG

  List<EPGProgram> guideFor(IPTVChannel channel, {DateTime? at}) {
    final list =
        epg['${channel.playlistId}::${channel.tvgId}'] ??
        epg['${channel.playlistId}::${channel.name}'] ??
        const <EPGProgram>[];
    return list;
  }

  EPGProgram? nowPlaying(IPTVChannel channel, {DateTime? at}) {
    final moment = at ?? DateTime.now();
    for (final p in guideFor(channel)) {
      if (!moment.isBefore(p.start) && moment.isBefore(p.stop)) return p;
    }
    return null;
  }

  EPGProgram? nextUp(IPTVChannel channel, {DateTime? at}) {
    final moment = at ?? DateTime.now();
    for (final p in guideFor(channel)) {
      if (p.start.isAfter(moment)) return p;
    }
    return null;
  }

  /// Channels airing something right now, soonest-ending first.
  List<NowOnAir> nowOnAir({int limit = 8}) {
    final out = <NowOnAir>[];
    for (final c in channels) {
      final p = nowPlaying(c);
      if (p != null) out.add(NowOnAir(c, p));
    }
    out.sort((a, b) => a.program.stop.compareTo(b.program.stop));
    return out.take(limit).toList();
  }

  void _pruneEpg() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 12));
    epg.removeWhere((_, list) {
      list.removeWhere((p) => p.stop.isBefore(cutoff));
      return list.isEmpty;
    });
  }

  Set<String> _epgChannelIds(IPTVPlaylist playlist) => channels
      .where((c) => c.playlistId == playlist.id)
      .expand((c) => [c.tvgId, c.name])
      .where((s) => s.isNotEmpty)
      .toSet();

  Future<Map<String, List<EPGProgram>>?> _loadEpg(
    String? url, {
    bool allowLocalNetwork = false,
  }) async {
    if (url == null || url.isEmpty) return null;
    try {
      SubscriptionReader.validateWebUri(Uri.parse(url));
      final xml = (await reader.read(
        url,
        allowLocalNetwork: allowLocalNetwork,
      )).text;
      final programs = XMLTVParser.parse(xml);
      if (programs.isEmpty) return null;
      return XMLTVParser.group(programs);
    } catch (e) {
      debugPrint('epg load failed');
      return null;
    }
  }

  String _nameFrom(String source) {
    final clean = source.split('?').first.replaceAll(RegExp(r'/+$'), '');
    final last = clean.split('/').last;
    return last.isEmpty ? '直播源' : last;
  }
}
