import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/local_scanner.dart';
import 'package:seewow/domain/media_item.dart';

void main() {
  test('an unreadable subfolder does not abort the whole scan', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-scan-');
    await File('${dir.path}/Good.Movie.2024.mkv').writeAsBytes([0, 1]);
    final locked = Directory('${dir.path}/locked')..createSync();
    await File('${locked.path}/Hidden.mkv').writeAsBytes([0]);
    await Process.run('chmod', ['000', locked.path]);
    try {
      final items = await LocalScanner().scan(
        MediaSource(
          id: 's',
          kind: SourceKind.local,
          name: 't',
          location: dir.path,
        ),
      );
      expect(items.length, 1);
      expect(items.single.title.toLowerCase(), contains('good'));
    } finally {
      await Process.run('chmod', ['755', locked.path]);
      await dir.delete(recursive: true);
    }
  });
}
