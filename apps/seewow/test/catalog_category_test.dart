import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/catalog_category.dart';
import 'package:seewow/domain/media_item.dart';

MediaItem _item({
  required String title,
  List<String> genres = const [],
  MediaKind kind = MediaKind.movie,
  String? showTitle,
  double duration = 0,
}) => MediaItem(
  id: title,
  sourceId: 's',
  kind: kind,
  title: title,
  showTitle: showTitle,
  locator: '/media/' + title,
  genres: genres,
  duration: duration,
);

void main() {
  test('documentaries are detected from genres and titles', () {
    expect(isDocumentary(_item(title: '蓝色星球', genres: ['纪录片'])), isTrue);
    expect(isDocumentary(_item(title: 'Planet Earth Documentary')), isTrue);
    expect(isDocumentary(_item(title: 'Dune Part Two', genres: ['科幻'])), isFalse);
    expect(
      isDocumentary(
        _item(title: 'Live at Home', kind: MediaKind.audio),
      ),
      isFalse,
    );
  });

  test('short dramas cover explicit labels and short episodes', () {
    expect(isShortDrama(_item(title: '闪婚总裁', genres: ['短剧'])), isTrue);
    expect(
      isShortDrama(
        _item(
          title: '第 1 集',
          showTitle: '微短剧',
          kind: MediaKind.episode,
          duration: 600,
        ),
      ),
      isTrue,
    );
    expect(
      isShortDrama(
        _item(
          title: '第 1 集',
          showTitle: 'Regular Show',
          kind: MediaKind.episode,
          duration: 40 * 60,
        ),
      ),
      isFalse,
    );
    expect(isShortDrama(_item(title: 'Some Movie', duration: 60)), isFalse);
  });

  test('filterCategory keeps order and returns empty for missing groups', () {
    final items = [
      _item(title: 'Doc', genres: ['纪实']),
      _item(title: 'Drama', genres: ['短剧']),
      _item(title: 'Movie'),
    ];
    expect(filterCategory(items, CatalogCategory.all), items);
    expect(
      filterCategory(items, CatalogCategory.documentary).single.title,
      'Doc',
    );
    expect(
      filterCategory(items, CatalogCategory.shortDrama).single.title,
      'Drama',
    );
    expect(
      filterCategory(items.take(1), CatalogCategory.shortDrama),
      isEmpty,
    );
  });

  test('refreshAll rescans enabled sources only', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-refresh-');
    try {
      final store = LibraryStore(directory: dir);
      store.sources.addAll([
        MediaSource(
          id: 'on',
          kind: SourceKind.local,
          name: 'on',
          location: dir.path,
        ),
        MediaSource(
          id: 'off',
          kind: SourceKind.local,
          name: 'off',
          location: dir.path,
          enabled: false,
        ),
      ]);
      final scanned = <String>[];
      store.scanner = (source) async {
        scanned.add(source.id);
        return <MediaItem>[];
      };
      await store.refreshAll();
      expect(scanned, ['on']);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
