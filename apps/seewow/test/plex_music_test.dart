import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/sources/plex_scanner.dart';

/// Plex returns music as an `artist` section whose `/all` listing is a flat
/// list of tracks (`type=10`). Before this change the scanner skipped such
/// sections entirely, so a linked Plex music library never reached the shelf.
Future<HttpServer> _server({int tracks = 1}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (path == '/library/sections') {
      request.response.write(
        jsonEncode({
          'MediaContainer': {
            'Directory': [
              {'key': '4', 'title': '音乐', 'type': 'artist', 'count': 1},
              {'key': '9', 'title': '照片', 'type': 'photo', 'count': 12},
            ],
          },
        }),
      );
    } else if (path == '/library/sections/4/all') {
      final isTracks = request.uri.queryParameters['type'] == '10';
      request.response.write(
        jsonEncode({
          'MediaContainer': {
            'totalSize': tracks,
            'Metadata': isTracks
                ? [
                    for (var n = 0; n < tracks; n++)
                      {
                        'ratingKey': '50$n',
                        'type': 'track',
                        'title': '夜航 $n',
                        'grandparentTitle': '林间乐队',
                        'parentTitle': '夜航',
                        'index': n + 1,
                        'parentIndex': 1,
                        'duration': 245000,
                        'addedAt': 1700000000,
                        'year': 2020,
                        'Genre': [
                          {'tag': '民谣'},
                        ],
                        'Media': [
                          {
                            'container': 'flac',
                            'bitrate': 900,
                            'Part': [
                              {
                                'key': '/library/parts/50$n/track.flac',
                                'size': 30000000,
                              },
                            ],
                          },
                        ],
                        'thumb': '/library/metadata/50$n/thumb/1',
                        'viewCount': 0,
                      },
                  ]
                : const <Map<String, dynamic>>[],
          },
        }),
      );
    } else {
      request.response.statusCode = 404;
      request.response.write('{}');
    }
    await request.response.close();
  });
  return server;
}

MediaSource _source(String uri, {List<String> folders = const []}) =>
    MediaSource(
      id: 'plex-music',
      kind: SourceKind.plex,
      name: '音乐 Plex',
      location: uri,
      folders: folders,
    );

void main() {
  late HttpServer server;
  late String base;

  setUp(() async {
    server = await _server();
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('sections expose music libraries alongside video ones', () async {
    final sections = await PlexScanner().sections(_source(base), 'token');
    expect(sections.map((s) => s.type), ['artist']);
    expect(sections.single.title, '音乐');
  });

  test('a music section is imported as playable audio tracks', () async {
    final items = await PlexScanner().scan(_source(base), 'token');
    expect(items.length, 1);
    final track = items.single;
    expect(track.kind, MediaKind.audio);
    expect(track.title, '夜航 0');
    expect(track.artist, '林间乐队');
    expect(track.album, '夜航');
    expect(track.duration, 245);
    expect(track.year, 2020);
    expect(track.genres, ['民谣']);
    expect(track.container, 'FLAC');
    expect(track.quality, '900 kbps');
    expect(
      track.locator,
      'http://127.0.0.1:${server.port}/library/parts/500/track.flac',
    );
    expect(track.posterUrl, contains('/library/metadata/500/thumb/1'));
    expect(track.httpHeaders['X-Plex-Token'], 'token');
    expect(track.position, 0);
  });

  test('the folder selection keeps music sections importable', () async {
    final items = await PlexScanner().scan(
      _source(base, folders: ['4']),
      'token',
    );
    expect(items.map((i) => i.kind), [MediaKind.audio]);
  });

  test('a selection without the music section skips it', () async {
    final items = await PlexScanner().scan(
      _source(base, folders: ['9']),
      'token',
    );
    expect(items, isEmpty);
  });
}
