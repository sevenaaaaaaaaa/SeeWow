import 'media_item.dart';

/// Local, explainable grouping used by the home shelves and library filters.
enum CatalogCategory { all, documentary, shortDrama }

const _documentaryWords = ['纪录', '纪实', 'documentary', 'docu'];
const _shortDramaWords = ['短剧', '微短剧', '竖屏', 'short drama', 'shortdrama'];

bool _matches(MediaItem item, List<String> words) {
  final haystack = [
    item.title,
    item.showTitle ?? '',
    ...item.genres,
  ].join(' ').toLowerCase();
  return words.any(haystack.contains);
}

bool isDocumentary(MediaItem item) =>
    item.kind != MediaKind.audio && _matches(item, _documentaryWords);

bool isShortDrama(MediaItem item) {
  if (item.kind == MediaKind.audio) return false;
  if (_matches(item, _shortDramaWords)) return true;
  return item.kind == MediaKind.episode &&
      item.duration > 0 &&
      item.duration <= 20 * 60;
}

List<MediaItem> filterCategory(
  Iterable<MediaItem> items,
  CatalogCategory category,
) {
  switch (category) {
    case CatalogCategory.all:
      return items.toList();
    case CatalogCategory.documentary:
      return items.where(isDocumentary).toList();
    case CatalogCategory.shortDrama:
      return items.where(isShortDrama).toList();
  }
}

String categoryLabel(CatalogCategory category) => switch (category) {
  CatalogCategory.all => '全部',
  CatalogCategory.documentary => '纪录片',
  CatalogCategory.shortDrama => '短剧',
};
