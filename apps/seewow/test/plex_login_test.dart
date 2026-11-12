import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/sources/plex_login.dart';

void main() {
  late HttpServer server;
  late Uri endpoint;
  var polls = 0;
  final seenHeaders = <String, String>{};

  setUp(() async {
    polls = 0;
    seenHeaders.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final response = request.response
        ..headers.contentType = ContentType.json;
      final path = request.uri.path;
      if (request.method == 'POST' && path == '/api/v2/pins') {
        for (final name in [
          'x-plex-client-identifier',
          'x-plex-product',
          'x-plex-version',
        ]) {
          final value = request.headers.value(name);
          if (value != null) seenHeaders[name] = value;
        }
        response.write(jsonEncode({'id': 42, 'code': 'ABCD'}));
      } else if (path == '/api/v2/pins/42') {
        polls++;
        response.write(jsonEncode({'authToken': polls > 1 ? 'token-1' : null}));
      } else if (path == '/api/v2/resources') {
        final header = request.headers.value('x-plex-token');
        if (header != 'token-1') response.statusCode = 401;
        response.write(
          jsonEncode([
            {
              'provides': 'server',
              'name': 'Home',
              'owned': true,
              'clientIdentifier': 'srv-1',
              'accessToken': 'server-token',
              'connections': [
                {'uri': 'https://relay.plex.direct:443', 'relay': true},
                {'uri': 'http://192.168.1.5:32400', 'local': true},
              ],
            },
            {'provides': 'client', 'name': 'Player'},
          ]),
        );
      } else {
        response.statusCode = 404;
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('PIN login polls until Plex returns a token', () async {
    final login = PlexLogin(endpoint: endpoint, clientId: 'test-client');
    final pin = await login.createPin();
    expect(pin.id, 42);
    expect(pin.code, 'ABCD');
    expect(seenHeaders['x-plex-client-identifier'], 'test-client');
    expect(seenHeaders['x-plex-product'], 'SeeWow');

    expect(await login.pollToken(pin.id), isNull);
    expect(await login.pollToken(pin.id), 'token-1');
  });

  test('account token lists owned servers and prefers LAN connections', () async {
    final login = PlexLogin(endpoint: endpoint, clientId: 'test-client');
    final servers = await login.servers('token-1');
    expect(servers, hasLength(1));
    expect(servers.single.name, 'Home');
    expect(servers.single.uri, 'http://192.168.1.5:32400');
    expect(servers.single.token, 'server-token');
  });

  test('connection ranking skips relays, credentials and invalid URIs', () {
    expect(
      PlexLogin.pickConnection([
        {'uri': 'https://user:pass@host:32400'},
        {'uri': 'ftp://host:32400'},
        {'uri': 'https://relay.plex.direct:443', 'relay': true},
        {'uri': 'http://host:32400', 'local': true},
      ]),
      'http://host:32400',
    );
    expect(
      PlexLogin.pickConnection([
        {'uri': 'https://secure.plex.direct:32400'},
        {'uri': 'http://plain.host:32400'},
      ]),
      'https://secure.plex.direct:32400',
    );
    expect(PlexLogin.pickConnection(const []), isNull);
  });

  test('servers without a usable connection are ignored', () {
    final servers = PlexLogin.parseServers([
      {'provides': 'server', 'name': 'Broken', 'connections': []},
      {'provides': 'client', 'name': 'Not a server'},
    ], 'account-token');
    expect(servers, isEmpty);
  });
}
