import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/filename_parser.dart';
import '../domain/media_item.dart';
import 'webdav_client.dart';

/// Walks a WebDAV tree and produces the same MediaItem shape as the local
/// scanner, with auth headers carried along for playback and artwork.
class WebDavScanner {
  WebDavScanner({this.maxDepth = 6, this.maxFiles = 3000});

  final int maxDepth;
  final int maxFiles;

  Future<List<MediaItem>> scan(MediaSource source, WebDavClient client) async {
    final items = <MediaItem>[];
    var visited = 0;

    bool isShowFolder(String name) {
      final l = name.toLowerCase();
      return l.contains('season') || l.contains('s0') || l.contains('第') || RegExp(r'^s\d+').hasMatch(l);
    }

    Future<void> walk(Uri dir, int depth, DavEntry? parentArt) async {
      if (depth > maxDepth || visited > maxFiles) return;
      List<DavEntry> entries;
      try {
        entries = await client.list(dir);
      } catch (e) {
        if (depth == 0) rethrow;
        return; // a single unreadable folder should not abort the whole scan
      }
      visited++;
      DavEntry? art;
      DavEntry? backdrop;
      for (final e in entries) {
        if (art == null && _isPoster(e.name)) art = e;
        if (backdrop == null && _isBackdrop(e.name)) backdrop = e;
      }
      final poster = art ?? parentArt;

      final parentName = entries.isEmpty ? dir.pathSegments.last : _leaf(dir.path);
      for (final entry in entries) {
        if (entry.name.startsWith('.')) continue;
        if (entry.isDir) {
          await walk(entry.url, depth + 1, poster);
          continue;
        }
        if (!entry.isVideo) continue;
        if (entry.name.toLowerCase().contains('sample')) continue;

        final parsed = FilenameParser.parse(
          entry.name,
          parentFolder: isShowFolder(parentName) ? parentName : null,
        );
        final isEpisode = parsed.season != null && parsed.episode != null;
        final showTitle = isEpisode ? (parsed.showTitle ?? _showFromPath(dir)) : null;
        final url = entry.url.toString();
        final ext = entry.name.split('.').last.toUpperCase();
        items.add(MediaItem(
          id: sha1.convert(utf8.encode(url)).toString().substring(0, 20),
          sourceId: source.id,
          kind: isEpisode ? MediaKind.episode : MediaKind.movie,
          title: isEpisode ? '第 ' + parsed.episode.toString() + ' 集' : parsed.title,
          locator: url,
          showTitle: showTitle,
          season: parsed.season,
          episode: parsed.episode,
          year: parsed.year,
          quality: parsed.quality,
          posterUrl: poster?.url.toString(),
          backdropUrl: backdrop?.url.toString() ?? poster?.url.toString(),
          addedAt: entry.modified,
          fileSize: entry.size,
          container: ext,
          httpHeaders: client.authHeaders,
        ));
        if (visited > maxFiles) return;
      }
    }

    await walk(client.baseUri, 0, null);
    items.sort((a, b) => (b.addedAt ?? DateTime(1970)).compareTo(a.addedAt ?? DateTime(1970)));
    return items;
  }

  static String _leaf(String path) {
    final segs = Uri.parse(path).pathSegments.where((s) => s.isNotEmpty).toList();
    return segs.isEmpty ? '' : segs.last;
  }

  static String? _showFromPath(Uri dir) {
    final segs = dir.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length < 2) return null;
    return segs[segs.length - 2];
  }

  static bool _isPoster(String name) {
    final l = name.toLowerCase();
    return l == 'poster.jpg' || l == 'folder.jpg' || l == 'cover.jpg' || l == 'poster.png';
  }

  static bool _isBackdrop(String name) {
    final l = name.toLowerCase();
    return l == 'fanart.jpg' || l == 'backdrop.jpg' || l == 'fanart.png';
  }
}
