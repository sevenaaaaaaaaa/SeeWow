import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/sources/public_domain_library.dart';

void main() {
  test('every bundled title is playable over https and credited', () {
    expect(publicDomainTitles, isNotEmpty);
    final ids = <String>{};
    for (final title in publicDomainTitles) {
      expect(ids.add(title.id), isTrue, reason: '${title.id} 重复');
      final stream = Uri.parse(title.streamUrl);
      expect(stream.scheme, 'https', reason: '${title.title} 必须走 https');
      expect(stream.host, isNotEmpty);
      expect(Uri.parse(title.posterUrl).scheme, 'https');
      expect(title.licence, isNotEmpty, reason: '${title.title} 缺少许可标注');
      expect(title.credit, isNotEmpty, reason: '${title.title} 缺少来源标注');
      expect(title.overview, isNotEmpty);
    }
  });

  test('items carry the licence through to the overview', () {
    final items = buildPublicDomainItems();
    expect(items.length, publicDomainTitles.length);
    for (final item in items) {
      expect(item.sourceId, publicDomainSourceId);
      expect(item.locator.startsWith('https://'), isTrue);
      expect(item.overview, contains('·'));
    }
  });

  test('loading twice never duplicates a title', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-sample-');
    try {
      final store = LibraryStore(directory: dir);
      expect(store.items, isEmpty);
      final first = await store.addItems(buildPublicDomainItems());
      expect(first, publicDomainTitles.length);
      final second = await store.addItems(buildPublicDomainItems());
      expect(second, 0);
      expect(store.items.length, publicDomainTitles.length);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
