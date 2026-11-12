import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/remote/remote_client.dart';
import 'package:seewow/remote/remote_hub.dart';
import 'package:seewow/remote/remote_server.dart';
import 'package:seewow/remote/remote_settings.dart';

class _FakePlayback implements RemotePlayback {
  @override
  String remoteTitle = 'Test Movie';
  @override
  Duration remotePosition = const Duration(seconds: 10);
  @override
  Duration remoteDuration = const Duration(minutes: 2);
  @override
  bool remotePlaying = false;
  @override
  double remoteVolume = 30;
  int toggles = 0;
  Duration? seeked;
  double? volumeSet;

  @override
  Future<void> remoteToggle() async {
    toggles++;
    remotePlaying = !remotePlaying;
  }

  @override
  Future<void> remoteSeek(Duration position) async {
    seeked = position;
    remotePosition = position;
  }

  @override
  Future<void> remoteSetVolume(double volume) async {
    volumeSet = volume;
    remoteVolume = volume;
  }
}

void main() {
  late RemoteServer server;
  late RemoteClient client;
  late _FakePlayback playback;

  setUp(() async {
    playback = _FakePlayback();
    RemoteHub.instance.attach(playback);
    server = RemoteServer();
    await server.start(
      code: '123456',
      name: 'Test Mac',
      httpPort: 0,
      udpPort: 0,
    );
    client = RemoteClient()
      ..configure('127.0.0.1', server.httpPort);
  });

  tearDown(() async {
    client.close();
    RemoteHub.instance.detach(playback);
    await server.stop();
  });

  test('pairing rejects the wrong code and accepts the right one', () async {
    await expectLater(client.pair('000000'), throwsA(isA<RemoteException>()));
    await client.pair('123456');
    expect(client.paired, isTrue);
  });

  test('status requires a token and reports the active playback', () async {
    await expectLater(client.status(), throwsA(isA<RemoteException>()));
    await client.pair('123456');
    final status = await client.status();
    expect(status.hasPlayback, isTrue);
    expect(status.title, 'Test Movie');
    expect(status.position, const Duration(seconds: 10));
    expect(status.duration, const Duration(minutes: 2));
    expect(status.volume, 30);
  });

  test('commands toggle, seek and set volume', () async {
    await client.pair('123456');
    var status = await client.command('toggle');
    expect(playback.toggles, 1);
    expect(status.playing, isTrue);

    status = await client.command('seek', 30);
    expect(playback.seeked, const Duration(seconds: 30));
    expect(status.position, const Duration(seconds: 30));

    status = await client.command('seekRelative', -10);
    expect(playback.seeked, const Duration(seconds: 20));

    status = await client.command('volume', 45);
    expect(playback.volumeSet, 45);
    expect(status.volume, 45);
  });

  test('seek is clamped to the media duration', () async {
    await client.pair('123456');
    await client.command('seek', 9999);
    expect(playback.seeked, const Duration(minutes: 2));
  });

  test('commands fail when nothing is playing', () async {
    await client.pair('123456');
    RemoteHub.instance.detach(playback);
    await expectLater(
      client.command('toggle'),
      throwsA(isA<RemoteException>()),
    );
  });

  test('UDP discovery replies with the HTTP port', () async {
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final reply = Completer<String>();
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = udp.receive();
      if (datagram != null && !reply.isCompleted) {
        reply.complete(utf8.decode(datagram.data));
      }
    });
    udp.send(
      utf8.encode('SEEWOW1 DISCOVER'),
      InternetAddress.loopbackIPv4,
      server.udpPort,
    );
    final text = await reply.future.timeout(const Duration(seconds: 2));
    expect(text, startsWith('SEEWOW1 '));
    final offer = jsonDecode(text.substring(8)) as Map<String, dynamic>;
    expect(offer['port'], server.httpPort);
    expect(offer['name'], 'Test Mac');
    udp.close();
  });

  test('settings persist the switch, port and code', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-remote-');
    try {
      final settings = RemoteSettings(directory: dir)
        ..enabled = true
        ..port = 47900
        ..code = '654321';
      await settings.save();
      final loaded = RemoteSettings(directory: dir);
      await loaded.load();
      expect(loaded.enabled, isTrue);
      expect(loaded.port, 47900);
      expect(loaded.code, '654321');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
