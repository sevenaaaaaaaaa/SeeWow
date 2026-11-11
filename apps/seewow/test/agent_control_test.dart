import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/agent/agent_controller.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-control-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('stopping a model request aborts network work and persists a cancelled task', () async {
    final received = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      await utf8.decoder.bind(r).join();
      received.complete();
    });
    final library = LibraryStore(directory: dir);
    final agent = AgentController(
      library,
      directory: dir,
      readSecret: (_) async => 'key',
    );
    await agent.configure('http://127.0.0.1:${server.port}/chat', 'model', '');
    final pending = agent.run('推荐电影');
    await received.future;
    agent.stop();
    final run = (await pending.timeout(const Duration(seconds: 3)))!;
    expect(run.cancelled, isTrue);
    expect(run.failed, isFalse);
    expect(agent.busy, isFalse);
    expect(run.steps.first.state, 'cancelled');
    final reload = AgentController(library, directory: dir);
    await reload.load();
    expect(reload.runs.single.cancelled, isTrue);
  });
  test(
    'stopping during a scan finishes that scan and skips all later steps',
    () async {
      final scanning = Completer<void>(), result = Completer<List<MediaItem>>();
      var scans = 0;
      final library = LibraryStore(directory: dir)
        ..sources.addAll([
          MediaSource(
            id: 'one',
            kind: SourceKind.local,
            name: 'One',
            location: '/one',
          ),
          MediaSource(
            id: 'two',
            kind: SourceKind.local,
            name: 'Two',
            location: '/two',
          ),
        ]);
      library.scanner = (_) {
        scans++;
        scanning.complete();
        return result.future;
      };
      final agent = AgentController(library, directory: dir);
      final pending = agent.run('刷新片源并检查片库');
      await scanning.future;
      agent.stop();
      expect(agent.busy, isTrue);
      result.complete([
        MediaItem(
          id: 'm',
          sourceId: 'one',
          kind: MediaKind.movie,
          title: 'Imported',
          locator: '/m',
        ),
      ]);
      final run = (await pending)!;
      expect(run.cancelled, isTrue);
      expect(scans, 1);
      expect(library.items.single.id, 'm');
      expect(run.steps.last.state, 'skipped');
      library.scanner = (_) async => [];
      expect((await agent.run('检查片库'))!.failed, isFalse);
    },
  );
  test('deleting a saved collection allows saving the task result again without duplicate writes', () async {
    final library = LibraryStore(directory: dir)
      ..items.add(
        MediaItem(
          id: 'm',
          sourceId: 's',
          kind: MediaKind.movie,
          title: 'Film',
          locator: '/m',
        ),
      );
    final agent = AgentController(library, directory: dir);
    final run = (await agent.run('生成片单'))!;
    await Future.wait([agent.saveCollection(run), agent.saveCollection(run)]);
    expect(library.collections.length, 1);
    await library.removeCollection(library.collections.single.id);
    expect(agent.collectionExists(run), isFalse);
    await agent.saveCollection(run);
    expect(library.collections.length, 1);
  });
}
