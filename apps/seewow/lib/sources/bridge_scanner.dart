import 'dart:convert';
import 'dart:io';

import '../domain/media_item.dart';

/// Phone side scanner for the desktop "computer library" bridge.
class BridgeScanner {
  BridgeScanner(this.source, this.token);

  final MediaSource source;
  final String token;
  HttpClient? _client;

  Future<List<MediaItem>> scan() async {
    final base = Uri.parse(source.location);
    final uri = base.replace(path: '/bridge/library');
    final client = _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set('X-SeeWow-Token', token);
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode != 200) {
        throw FormatException('电脑媒体库返回 HTTP ${response.statusCode}');
      }
      final raw = jsonDecode(body);
      if (raw is! Map || raw['items'] is! List) {
        throw const FormatException('电脑媒体库响应格式无效');
      }
      final items = <MediaItem>[];
      for (final entry in (raw['items'] as List).whereType<Map>()) {
        final remoteId = entry['id']?.toString() ?? '';
        final stream = entry['stream']?.toString() ?? '';
        if (remoteId.isEmpty || stream.isEmpty) continue;
        items.add(
          MediaItem(
            id: '${source.id}:$remoteId',
            sourceId: source.id,
            sourceRef: remoteId,
            kind: MediaKind.values.firstWhere(
              (kind) => kind.name == entry['kind']?.toString(),
              orElse: () => MediaKind.other,
            ),
            title: entry['title']?.toString() ?? '未命名',
            showTitle: entry['showTitle']?.toString(),
            season: (entry['season'] as num?)?.toInt(),
            episode: (entry['episode'] as num?)?.toInt(),
            year: (entry['year'] as num?)?.toInt(),
            quality: entry['quality']?.toString() ?? '',
            duration: (entry['duration'] as num? ?? 0).toDouble(),
            fileSize: (entry['fileSize'] as num? ?? 0).toInt(),
            locator: stream,
            posterUrl: entry['poster']?.toString(),
            httpHeaders: const {},
          ),
        );
      }
      return items;
    } finally {
      close();
    }
  }

  void close() {
    _client?.close(force: true);
    _client = null;
  }
}
