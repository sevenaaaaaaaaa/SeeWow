import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/iptv.dart';
import '../domain/xmltv.dart';

/// A channel that is on air right now, used by the "正在播" rail.
class NowOnAir {
  NowOnAir(this.channel, this.program);
  final IPTVChannel channel;
  final EPGProgram program;
}

/// IPTV playlists, channels, EPG and favourites, persisted next to the
/// movie library as plain JSON.
class IPTVStore extends ChangeNotifier {
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
    final support = await getApplicationSupportDirectory();
    final d = Directory(support.path + '/SeeWow');
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
        ..addAll((raw['playlists'] as List? ?? []).map((e) => IPTVPlaylist.fromJson(e as Map<String, dynamic>)));
      channels
        ..clear()
        ..addAll((raw['channels'] as List? ?? []).map((e) => IPTVChannel.fromJson(e as Map<String, dynamic>)));
      epg.clear();
      final rawEpg = raw['epg'] as Map<String, dynamic>? ?? {};
      rawEpg.forEach((key, value) {
        epg[key] = (value as List).map((e) => EPGProgram.fromJson(e as Map<String, dynamic>)).toList();
      });
      favorites
        ..clear()
        ..addAll((raw['favorites'] as List? ?? []).map((e) => e as String));
      recents
        ..clear()
        ..addAll((raw['recents'] as List? ?? []).map((e) => e as String));
      _pruneEpg();
      notifyListeners();
    } catch (e) {
      debugPrint('iptv load failed: ' + e.toString());
    }
  }

  Future<void> save() async {
    final d = await _dir();
    final payload = jsonEncode({
      'playlists': playlists.map((e) => e.toJson()).toList(),
      'channels': channels.map((e) => e.toJson()).toList(),
      'epg': epg.map((key, value) => MapEntry(key, value.map((e) => e.toJson()).toList())),
      'favorites': favorites,
      'recents': recents,
    });
    await File(d.path + '/iptv.json').writeAsString(payload);
  }

  /// Accepts an http(s) M3U url or a local .m3u/.m3u8 file path.
  Future<bool> addPlaylist({required String name, required String source, String? epgUrl}) async {
    loading = true;
    toast = null;
    notifyListeners();
    try {
      final text = await _read(source);
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final parsed = M3UParser.parse(text, playlistId: id);
      if (parsed.isEmpty) {
        toast = '这个列表里没有可播放的频道';
        return false;
      }
      channels.addAll(parsed);
      var playlist = IPTVPlaylist(
        id: id,
        name: name.trim().isEmpty ? _nameFrom(source) : name.trim(),
        source: source,
        channelCount: parsed.length,
        updatedAt: DateTime.now(),
        epgUrl: (epgUrl != null && epgUrl.trim().isNotEmpty) ? epgUrl.trim() : null,
      );
      final guide = await _loadEpg(playlist.epgUrl);
      if (guide != null) {
        epg.addAll(guide);
        playlist = playlist.copyWith(epgCount: guide.values.fold<int>(0, (sum, list) => sum + list.length));
      }
      playlists.add(playlist);
      await save();
      toast = '已添加 ' + parsed.length.toString() + ' 个频道' + (playlist.epgCount > 0 ? '，' + playlist.epgCount.toString() + ' 条节目' : '');
      return true;
    } catch (e) {
      toast = '读取失败：' + e.toString();
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reload(IPTVPlaylist playlist) async {
    loading = true;
    notifyListeners();
    try {
      final text = await _read(playlist.source);
      final parsed = M3UParser.parse(text, playlistId: playlist.id);
      channels.removeWhere((c) => c.playlistId == playlist.id);
      channels.addAll(parsed);
      final idx = playlists.indexWhere((p) => p.id == playlist.id);
      if (idx >= 0) {
        playlists[idx] = playlist.copyWith(channelCount: parsed.length, updatedAt: DateTime.now());
      }
      await save();
      toast = '已更新 ' + parsed.length.toString() + ' 个频道';
      if (playlist.epgUrl != null) await refreshEpg(playlist);
    } catch (e) {
      toast = '更新失败：' + e.toString();
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
      final guide = await _loadEpg(url);
      if (guide == null) throw StateError('节目单为空');
      final oldIds = epg.keys.where((k) => _epgChannelIds(playlist).contains(k)).toList();
      for (final id in oldIds) {
        epg.remove(id);
      }
      epg.addAll(guide);
      final count = guide.values.fold<int>(0, (sum, list) => sum + list.length);
      final idx = playlists.indexWhere((p) => p.id == playlist.id);
      if (idx >= 0) playlists[idx] = playlists[idx].copyWith(epgCount: count);
      await save();
      toast = '节目单已更新：' + count.toString() + ' 条';
    } catch (e) {
      toast = '节目单更新失败：' + e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setEpgUrl(IPTVPlaylist playlist, String url) async {
    final idx = playlists.indexWhere((p) => p.id == playlist.id);
    if (idx < 0) return;
    playlists[idx] = playlists[idx].copyWith(epgUrl: url.trim().isEmpty ? null : url.trim());
    await save();
    notifyListeners();
    if (url.trim().isNotEmpty) await refreshEpg(playlists[idx]);
  }

  Future<void> removePlaylist(IPTVPlaylist playlist) async {
    playlists.removeWhere((p) => p.id == playlist.id);
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
    return channels.where((c) => c.name.toLowerCase().contains(q) || c.group.toLowerCase().contains(q)).toList();
  }

  // ---------------------------------------------------------------- favourites

  bool isFavorite(IPTVChannel channel) => favorites.contains(channel.id);

  Future<void> toggleFavorite(IPTVChannel channel) async {
    if (!favorites.remove(channel.id)) favorites.add(channel.id);
    await save();
    notifyListeners();
  }

  List<IPTVChannel> get favoriteChannels => channels.where((c) => favorites.contains(c.id)).toList();

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
    final list = epg[channel.tvgId] ?? epg[channel.name] ?? const <EPGProgram>[];
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

  Set<String> _epgChannelIds(IPTVPlaylist playlist) => channels.where((c) => c.playlistId == playlist.id).expand((c) => [c.tvgId, c.name]).where((s) => s.isNotEmpty).toSet();

  Future<Map<String, List<EPGProgram>>?> _loadEpg(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final xml = await _read(url);
      final programs = XMLTVParser.parse(xml);
      if (programs.isEmpty) return null;
      return XMLTVParser.group(programs);
    } catch (e) {
      debugPrint('epg load failed: ' + e.toString());
      return null;
    }
  }

  Future<String> _read(String source) async {
    if (source.startsWith('http://') || source.startsWith('https://')) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(source));
        request.headers.set(HttpHeaders.userAgentHeader, 'SeeWow/1.0');
        final response = await request.close().timeout(const Duration(seconds: 25));
        if (response.statusCode >= 400) {
          throw HttpException('HTTP ' + response.statusCode.toString());
        }
        return await response.transform(utf8.decoder).join();
      } finally {
        client.close(force: true);
      }
    }
    final file = File(source);
    if (!await file.exists()) throw FileSystemException('文件不存在', source);
    return file.readAsString();
  }

  String _nameFrom(String source) {
    final clean = source.split('?').first.replaceAll(RegExp(r'/+$'), '');
    final last = clean.split('/').last;
    return last.isEmpty ? '直播源' : last;
  }
}
