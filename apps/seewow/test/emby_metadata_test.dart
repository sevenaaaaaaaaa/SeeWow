import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/metadata/emby_metadata_client.dart';

/// The server's wire format is the contract here, so the test speaks it over a
/// real loopback socket rather than mocking the transport.
void main() {
  late HttpServer server;
  late String base;
  late List<Uri> seen;
  late List<String?> tokens;

  setUp(() async {
    seen = [];
    tokens = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seen.add(request.uri);
      tokens.add(request.headers.value('x-emby-token'));
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      if (path == '/Items' ||
          path.startsWith('/Items/') ||
          path.startsWith('/Users/')) {
        if (path.endsWith('/Items')) {
          request.response.write(jsonEncode({
            'TotalRecordCount': 2,
            'Items': [
              {
                'Id': 'a1b2c3d4-0000-0000-0000-0000000000ff',
                'Type': 'Movie',
                'Name': '银翼杀手',
                'OriginalTitle': 'Blade Runner',
                'Overview': '<p>洛杉矶的雨夜。</p>',
                'ProductionYear': 1982,
                'Genres': ['科幻', '惊悚'],
                'CommunityRating': 8.2,
                'RunTimeTicks': 70200000000,
                'ProductionLocations': ['US'],
                'ImageTags': {'Primary': 'tag'},
                'BackdropImageTags': ['backdrop'],
                'ProviderIds': {'Tmdb': '78', 'Imdb': 'tt0083658'},
                'People': [
                  {'Name': 'Ridley Scott', 'Type': 'Director', 'Role': '导演'},
                  {'Name': 'Harrison Ford', 'Type': 'Actor', 'Role': 'Deckard'},
                ],
              },
              {'Id': '', 'Type': 'Movie', 'Name': ''},
            ],
          }));
        } else {
          request.response.write(jsonEncode({
            'Id': 'a1b2c3d4-0000-0000-0000-0000000000ff',
            'Type': 'Movie',
            'Name': '银翼杀手',
            'Overview': '完整简介',
            'ProductionYear': 1982,
            'Genres': ['科幻'],
            'CommunityRating': 8.2,
          }));
        }
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() => server.close(force: true));

  test('search maps the server record and drops unusable entries', () async {
    final client = EmbyMetadataSource(
      base: Uri.parse(base),
      token: 'secret-token',
      userId: 'user-1',
      kind: 'jellyfin',
      serverName: '客厅 NAS',
    );
    final results = await client.search('银翼', series: false);
    expect(seen.single.path, '/Users/user-1/Items');
    expect(seen.single.queryParameters['SearchTerm'], '银翼');
    expect(seen.single.queryParameters['IncludeItemTypes'], 'Movie');
    expect(tokens.single, 'secret-token');
    expect(results.length, 1);
    final movie = results.single;
    expect(movie.title, '银翼杀手');
    expect(movie.originalTitle, 'Blade Runner');
    expect(movie.overview, '洛杉矶的雨夜。');
    expect(movie.year, 1982);
    expect(movie.genres, ['科幻', '惊悚']);
    expect(movie.rating, 8.2);
    expect(movie.duration, closeTo(7020, 0.1));
    expect(movie.provider, 'jellyfin');
    expect(movie.countries, ['US']);
    expect(movie.posterUrl, contains('/Items/a1b2c3d4-0000-0000-0000-0000000000ff/Images/Primary'));
    expect(movie.backdropUrl, contains('/Images/Backdrop/0'));
    expect(movie.externalIds['tmdb'], '78');
    expect(movie.externalIds['jellyfin'], 'a1b2c3d4-0000-0000-0000-0000000000ff');
    expect(movie.people.map((p) => p.name), containsAll(['Ridley Scott', 'Harrison Ford']));
    expect(
      movie.people.firstWhere((p) => p.name == 'Harrison Ford').department,
      'Cast',
    );
    expect(client.label, '客厅 NAS（jellyfin 服务器）');
    client.close();
  });

  test('details reads the GUID back through externalIds', () async {
    final client = EmbyMetadataSource(
      base: Uri.parse(base),
      token: 'secret-token',
      kind: 'emby',
    );
    final results = await client.search('银翼', series: false);
    final full = await client.details(results.single);
    expect(seen.last.path, '/Items/a1b2c3d4-0000-0000-0000-0000000000ff');
    expect(full.overview, '完整简介');
    expect(full.provider, 'emby');
    client.close();
  });

  test('a series lookup asks for Series instead of Movie', () async {
    final client = EmbyMetadataSource(
      base: Uri.parse(base),
      token: 't',
    );
    await client.search('剧名', series: true);
    expect(seen.single.queryParameters['IncludeItemTypes'], 'Series');
    expect(seen.single.path, '/Items');
    client.close();
  });

  test('an empty query never touches the network', () async {
    final client = EmbyMetadataSource(base: Uri.parse(base), token: 't');
    expect(await client.search('   ', series: false), isEmpty);
    expect(seen, isEmpty);
    client.close();
  });
}
