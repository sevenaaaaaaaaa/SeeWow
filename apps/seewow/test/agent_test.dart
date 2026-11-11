import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/agent/agent_controller.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';

void main() {
  late Directory dir;
  late LibraryStore library;
  late AgentController agent;
  late HttpServer server;
  final requests = <Map<String, dynamic>>[];
  var steps = <Map<String, dynamic>>[];
  var httpStatus = 200;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-agent-test-');
    library = LibraryStore(directory: dir)
      ..items.add(
        MediaItem(
          id: 'real',
          sourceId: 'nas',
          kind: MediaKind.movie,
          title: 'Real Movie',
          locator: '/private/media/real.mkv',
          genres: ['科幻'],
          duration: 5400,
          httpHeaders: {'Authorization': 'private-password'},
        ),
      );
    library.sources.add(
      MediaSource(
        id: 'nas',
        kind: SourceKind.smb,
        name: 'private NAS',
        location: 'smb://private-server/share',
        username: 'secret-user',
      ),
    );
    agent = AgentController(
      library,
      directory: dir,
      readSecret: (_) async => 'test-key',
      writeSecret: (_, _) async {},
    );
    requests.clear();
    httpStatus = 200;
    steps = [
      {
        'tool': 'recommend',
        'ids': ['real'],
        'query': '符合科幻偏好',
      },
      {'tool': 'build_collection', 'name': '周末科幻'},
    ];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'POST') {
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.statusCode = httpStatus;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({'steps': steps}),
                },
              },
            ],
          }),
        );
      } else {
        request.response.write(
          '<a href="/feeds/tv.m3u">TV</a> https://example.test/dav/',
        );
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  Future<void> model() => agent.configure(
    'http://127.0.0.1:${server.port}/v1/chat/completions',
    'mock',
    '',
  );
  test(
    'local plan produces a durable collection preview and idempotent save',
    () async {
      final run = (await agent.run('生成科幻片单'))!;
      expect(run.mode, '本地规则');
      expect(run.failed, isFalse);
      expect(run.itemIds, ['real']);
      expect(library.collections, isEmpty);
      await agent.saveCollection(run);
      await agent.saveCollection(run);
      expect(library.collections.length, 1);
      final reloaded = AgentController(library, directory: dir);
      await reloaded.load();
      expect(reloaded.runs.single.savedCollectionId, isNotNull);
    },
  );
  test('model plans execute real tools while catalog omits locators and credentials', () async {
    await model();
    final run = (await agent.run('给我生成一份科幻片单'))!;
    expect(run.failed, isFalse);
    expect(run.itemIds, ['real']);
    expect(run.collectionName, '周末科幻');
    final request = jsonEncode(requests.single);
    for (final secret in [
      'private-server',
      'secret-user',
      'private-password',
      '/private/media',
      'test-key',
    ]) {
      expect(request, isNot(contains(secret)));
    }
    expect(library.collections, isEmpty);
    await agent.saveCollection(run);
    expect(library.collections.single.name, '周末科幻');
  });
  test('invented IDs fail without mutating the library', () async {
    await model();
    steps = [
      {
        'tool': 'recommend',
        'ids': ['invented'],
      },
    ];
    final run = (await agent.run('推荐电影'))!;
    expect(run.failed, isTrue);
    expect(run.itemIds, isEmpty);
    expect(library.collections, isEmpty);
  });
  test('Telegram-origin media is excluded from the model catalog', () async {
    library.items.add(
      MediaItem(
        id: 'tg-private',
        sourceId: 'telegram',
        kind: MediaKind.movie,
        title: 'Private Telegram Course',
        locator: '/telegram/course.mp4',
        aiAllowed: false,
      ),
    );
    await model();
    await agent.run('推荐电影');
    expect(
      jsonEncode(requests.single),
      isNot(contains('Private Telegram Course')),
    );
    expect(jsonEncode(requests.single), isNot(contains('tg-private')));
    steps = [
      {
        'tool': 'recommend',
        'ids': ['tg-private'],
      },
    ];
    expect((await agent.run('推荐电影'))!.failed, isTrue);
  });
  test('an unrequested refresh and arbitrary tools are rejected', () async {
    await model();
    steps = [
      {'tool': 'refresh_sources'},
    ];
    expect((await agent.run('推荐电影'))!.failed, isTrue);
    steps = [
      {'tool': 'delete_files'},
    ];
    expect((await agent.run('整理片库'))!.failed, isTrue);
    expect(library.items.length, 1);
  });
  test('HTTP failure is visible and allows a retry in local mode', () async {
    await model();
    httpStatus = 401;
    final run = (await agent.run('推荐电影'))!;
    expect(run.failed, isTrue);
    expect(run.summary, contains('HTTP 401'));
    expect(agent.busy, isFalse);
    await agent.configure('', '', '');
    expect((await agent.run('推荐电影'))!.failed, isFalse);
  });
  test(
    'page collection resolves relative M3U links and never auto imports',
    () async {
      final url = 'http://127.0.0.1:${server.port}/index';
      final found = await SourceDiscovery.collect(url);
      expect(found, contains('http://127.0.0.1:${server.port}/feeds/tv.m3u'));
      final run = (await agent.run('收集 $url'))!;
      expect(
        run.candidates,
        contains('http://127.0.0.1:${server.port}/feeds/tv.m3u'),
      );
      expect(library.sources.length, 1);
      expect(requests, isEmpty);
    },
  );
  test('discovery excludes embedded credentials; remote HTTP model keys are blocked', () async {
    expect(
      SourceDiscovery.extract(
        'smb://nas/Movies https://user:pass@example.test/dav/',
      ),
      ['smb://nas/Movies'],
    );
    await expectLater(
      agent.configure('http://remote.test/v1/chat/completions', 'm', 'key'),
      throwsFormatException,
    );
  });
  test(
    'refresh failure remains a failed task rather than successful completion',
    () async {
      library.scanner = (_) async => throw const FileSystemException('offline');
      final run = (await agent.run('刷新片源并检查片库'))!;
      expect(run.failed, isTrue);
      expect(run.steps.last.state, 'skipped');
      expect(library.items.length, 1);
    },
  );
}
