import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seewow/playback/speech_synthesizer.dart';

/// iOS 语音后端的通道协议与失败语义。macOS 宿主跑不了 Platform.isIOS，
/// 所以用 platformOverride 注入模拟 iOS，通道用 mock 应答。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('seewow/voice');
  final probeCalls = <MethodCall>[];
  final synthCalls = <MethodCall>[];

  setUp(() {
    probeCalls.clear();
    synthCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'tts.probe') {
            probeCalls.add(call);
            return true;
          }
          if (call.method == 'tts.synthesize') {
            synthCalls.add(call);
            final path = call.arguments?['path'] as String?;
            if (path != null) {
              final file = File(path);
              await file.writeAsBytes(
                Uint8List(200),
                mode: FileMode.append,
              );
            }
            return path;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('iOS 探测成功时后端记为 ios', () async {
    final synthesizer = SpeechSynthesizer(platformOverride: 'ios');
    expect(await synthesizer.backend(), 'ios');
    expect(probeCalls, hasLength(1));
    // 结果缓存：第二次不再发探测。
    expect(await synthesizer.backend(), 'ios');
    expect(probeCalls, hasLength(1));
  });

  test('iOS 没有系统语音时后端如实返回 null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final synthesizer = SpeechSynthesizer(platformOverride: 'ios');
    expect(await synthesizer.backend(), isNull);
  });

  test('合成委托原生通道并校验产物', () async {
    final directory = await Directory.systemTemp.createTemp('seewow-tts');
    try {
      final synthesizer = SpeechSynthesizer(platformOverride: 'ios');
      final wav = await synthesizer.synthesize(
        '保罗与契提曼人并肩作战。',
        directory: directory,
        languageHint: 'zh-CN',
      );
      expect(wav, isNotNull);
      expect(await wav!.length(), 200);
      expect(synthCalls, hasLength(1));
      expect(synthCalls.single.arguments?['text'], '保罗与契提曼人并肩作战。');
      expect(synthCalls.single.arguments?['language'], 'zh-CN');
      expect(synthCalls.single.arguments?['path'], wav.path);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('原生没有产出时按合成失败抛出', () async {
    // 探测成功（引擎存在）但合成不落盘：引擎失败要抛，而不是静默不可用。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'tts.probe') return true;
          return null;
        });
    final directory = await Directory.systemTemp.createTemp('seewow-tts');
    try {
      final synthesizer = SpeechSynthesizer(platformOverride: 'ios');
      expect(
        () => synthesizer.synthesize('空山不见人', directory: directory),
        throwsFormatException,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('空白文本不调用通道直接返回 null', () async {
    final directory = await Directory.systemTemp.createTemp('seewow-tts');
    try {
      final synthesizer = SpeechSynthesizer(platformOverride: 'ios');
      expect(
        await synthesizer.synthesize('   ', directory: directory),
        isNull,
      );
      expect(synthCalls, isEmpty);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
