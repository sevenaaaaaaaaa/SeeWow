import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/metadata/bangumi_client.dart';
import 'package:seewow/metadata/metadata_source.dart';
import 'package:seewow/metadata/tvmaze_client.dart';

/// A real HTTP server: these clients speak the services' wire formats, and a
/// mocked transport would hide a wrong path or a wrong field name.
Future<HttpServer> serve(void Function(HttpRequest request, String body) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    handle(request, body);
    await request.response.close();
  });
  return server;
}

void main() {
  group('TVmaze', () {
    late HttpServer server;
    late String base;

    setUp(() async {
      server = await serve((request, body) {
        final path = request.uri.path;
        if (path == '/search/shows') {
          request.response.write(jsonEncode([
            {
              'score': 0.9,
              'show': {
                'id': 82,
                'name': 'Game of Thrones',
                'language': 'English',
                'genres': ['Drama', 'Adventure'],
                'premiered': '2011-04-17',
                'runtime': 60,
                'rating': {'average': 9.1},
                'network': {
                  'country': {'name': 'United States'},
                },
                'image': {'original': 'https://example.test/got.jpg'},
                'summary': '<p>A <b>long</b> winter &amp; seven kingdoms.</p>',
                'externals': {'imdb': 'tt0944947', 'tvdb': 121361},
              },
            },
            {
              'show': {'id': 0, 'name': ''},
            },
          ]));
        } else if (path == '/shows/82') {
          request.response.write(jsonEncode({
            'id': 82,
            'name': 'Game of Thrones',
            'premiered': '2011-04-17',
            'runtime': 60,
            'genres': ['Drama'],
            'rating': {'average': 9.1},
            'summary': '<p>Winter.</p>',
          }));
        } else if (path == '/shows/82/crew') {
          request.response.write(jsonEncode([
            {
              'type': 'Director',
              'person': {'id': 1, 'name': 'Tim Van Patten'},
            },
            {
              'type': 'Creator',
              'person': {'id': 2, 'name': 'David Benioff'},
            },
          ]));
        } else {
          request.response.statusCode = 404;
          request.response.write('{}');
        }
      });
      base = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() => server.close(force: true));

    test('search maps the wire format and drops unusable entries', () async {
      final client = TvMazeClient(base: Uri.parse(base));
      final results = await client.search('game', series: true);
      expect(results.length, 1);
      final show = results.single;
      expect(show.id, 82);
      expect(show.title, 'Game of Thrones');
      expect(show.mediaType, 'tv');
      expect(show.year, 2011);
      expect(show.genres, ['Drama', 'Adventure']);
      expect(show.rating, 9.1);
      expect(show.duration, 3600);
      expect(show.countries, ['United States']);
      expect(show.externalIds['imdb'], 'tt0944947');
      client.close();
    });

    test('HTML in summaries becomes plain text', () async {
      final client = TvMazeClient(base: Uri.parse(base));
      final results = await client.search('game', series: true);
      expect(results.single.overview, 'A long winter & seven kingdoms.');
      client.close();
    });

    test('details merges the crew and keeps the title when crew fails', () async {
      final client = TvMazeClient(base: Uri.parse(base));
      final search = await client.search('game', series: true);
      final full = await client.details(search.single);
      expect(full.people.map((p) => p.name), contains('Tim Van Patten'));
      expect(
        full.people.firstWhere((p) => p.name == 'Tim Van Patten').department,
        'Directing',
      );
      expect(full.overview, 'Winter.');
      client.close();
    });

    test('a year filter removes mismatches', () async {
      final client = TvMazeClient(base: Uri.parse(base));
      final results = await client.search('game', series: true, year: 2015);
      expect(results, isEmpty);
      client.close();
    });

    test('it declares itself series-only so films never see it', () {
      expect(TvMazeClient().seriesOnly, isTrue);
      TvMazeClient().close();
    });
  });

  group('Bangumi', () {
    late HttpServer server;
    late String base;

    setUp(() async {
      server = await serve((request, body) {
        final path = request.uri.path;
        if (path == '/v0/search/subjects') {
          expect(request.method, 'POST');
          expect(request.headers.value('user-agent'), contains('SeeWow'));
          final payload = jsonDecode(body) as Map<String, dynamic>;
          expect(payload['keyword'], '进击');
          expect((payload['filter'] as Map)['type'], [2]);
          request.response.write(jsonEncode({
            'total': 1,
            'data': [
              {
                'id': 235264,
                'name': '進撃の巨人',
                'name_cn': '进击的巨人',
                'date': '2013-04-07',
                'summary': '<p>城墙之外的世界。</p>',
                'images': {'large': 'https://example.test/aot.jpg'},
                'rating': {'score': 8.9, 'total': 12000},
                'tags': [
                  {'name': 'TV', 'count': 900},
                  {'name': '战斗', 'count': 1},
                ],
              },
            ],
          }));
        } else if (path == '/v0/subjects/235264') {
          request.response.write(jsonEncode({
            'id': 235264,
            'name': '進撃の巨人',
            'name_cn': '进击的巨人',
            'date': '2013-04-07',
            'summary': '<p>城墙之外的世界。</p>',
            'images': {'large': 'https://example.test/aot.jpg'},
            'rating': {'score': 8.9, 'total': 12000},
            'infobox': [
              {
                'key': '放送开始',
                'value': '2013年4月7日',
              },
              {
                'key': '话数',
                'value': '25',
              },
            ],
          }));
        } else if (path == '/v0/subjects/235264/persons') {
          request.response.write(jsonEncode([
            {'name': '荒木哲郎', 'relation': '导演'},
            {'name': '谏山创', 'relation': '原作'},
          ]));
        } else {
          request.response.statusCode = 404;
          request.response.write('{}');
        }
      });
      base = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() => server.close(force: true));

    test('search sends the v0 body and maps the response', () async {
      final client = BangumiClient(base: Uri.parse(base));
      final results = await client.search('进击', series: true);
      final show = results.single;
      expect(show.id, 235264);
      expect(show.title, '进击的巨人');
      expect(show.originalTitle, '進撃の巨人');
      expect(show.overview, '城墙之外的世界。');
      expect(show.year, 2013);
      // Bangumi scores out of 10, this app renders out of 5.
      expect(show.rating, closeTo(4.45, 0.001));
      expect(show.ratings.single.scale, 10);
      // A tag with one vote is noise, not a genre.
      expect(show.genres, ['TV']);
      client.close();
    });

    test('details reads infobox dates and staff', () async {
      final client = BangumiClient(base: Uri.parse(base));
      final search = await client.search('进击', series: true);
      final full = await client.details(search.single);
      expect(full.year, 2013);
      expect(full.people.map((p) => p.name), contains('荒木哲郎'));
      expect(
        full.people.firstWhere((p) => p.name == '荒木哲郎').department,
        'Directing',
      );
      client.close();
    });

    test('plain text helper strips markup and entities', () {
      expect(plainText('<p>a<br/>b &amp; c</p>'), 'a\nb & c');
      expect(plainText(null), '');
      expect(yearOf('2013-04-07'), 2013);
      expect(yearOf(''), isNull);
      expect(yearOf(null), isNull);
    });
  });
}
