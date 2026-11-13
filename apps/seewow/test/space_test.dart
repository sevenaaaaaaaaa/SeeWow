import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';

void main() {
  test('two spaces persist separate sources', () async {
    final root = await Directory.systemTemp.createTemp('seewow-space-');
    final dirA = Directory('${root.path}/a');
    final dirB = Directory('${root.path}/b');
    try {
      final main = LibraryStore(directory: dirA);
      final space = LibraryStore(directory: dirB, space: 2);
      expect(main.space, 1);
      expect(space.space, 2);
      main.sources.add(
        MediaSource(
          id: 'main',
          kind: SourceKind.local,
          name: '主空间文件夹',
          location: dirA.path,
        ),
      );
      space.sources.add(
        MediaSource(
          id: 'space',
          kind: SourceKind.local,
          name: '解耦文件夹',
          location: dirB.path,
        ),
      );
      await main.save();
      await space.save();

      final mainAgain = LibraryStore(directory: dirA);
      final spaceAgain = LibraryStore(directory: dirB, space: 2);
      await mainAgain.load();
      await spaceAgain.load();
      expect(mainAgain.sources.map((s) => s.id), ['main']);
      expect(spaceAgain.sources.map((s) => s.id), ['space']);
      expect(mainAgain.items, isEmpty);
      expect(spaceAgain.items, isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
