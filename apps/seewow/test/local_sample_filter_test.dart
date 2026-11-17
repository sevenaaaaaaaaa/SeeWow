import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/local_scanner.dart';
import 'package:seewow/domain/media_item.dart';

void main() {
  test('RM-09 片名里出现 sample 的正片不被跳过，真正的样片仍被跳过', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-sample-');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/The Sampler.mkv').writeAsString('x');
    await File('${dir.path}/Movie.2024.sample.mkv').writeAsString('x');
    await File('${dir.path}/Another Film.mkv').writeAsString('x');
    final items = await LocalScanner().scan(
      MediaSource(id: 'l', kind: SourceKind.local, name: '本地', location: dir.path),
    );
    final titles = items.map((i) => i.title).toList();
    expect(titles, contains('The Sampler'));
    expect(titles, contains('Another Film'));
    expect(items.length, 2);
  });
}