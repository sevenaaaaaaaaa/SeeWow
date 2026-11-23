import '../domain/media_metadata.dart';
import '../domain/media_review.dart';

/// One metadata service the library can query.
///
/// TMDB, TVmaze and Bangumi answer in three different shapes; the dialog only
/// ever sees this interface, so adding a service never touches the UI again.
abstract class MetadataSource {
  String get id;
  String get label;

  /// True when the service can only answer for series, not films.
  bool get seriesOnly;

  Future<List<MediaMetadata>> search(
    String query, {
    required bool series,
    int? year,
    int page = 1,
  });

  Future<MediaMetadata> details(MediaMetadata candidate);

  /// 这个源能不能给评论。
  ///
  /// 默认 false：TMDB 要额外参数、TVmaze 根本没有评论，让它们「支持评论」只会
  /// 让界面多一次空请求。支持的源才实现 [reviews]。
  bool get supportsReviews => false;

  /// 拉这个条目的评论。不支持的源返回空表，而不是抛错或假装查过。
  Future<List<MediaReview>> reviews(MediaMetadata candidate, {int limit = 10}) async =>
      const [];

  void close();
}

/// HTML in TVmaze summaries and Bangumi descriptions is invisible in this app,
/// so it is stripped once here instead of leaking into every view.
String plainText(String? html) {
  if (html == null) return '';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

int? yearOf(String? date) {
  if (date == null || date.length < 4) return null;
  final year = int.tryParse(date.substring(0, 4));
  return year != null && year > 1800 && year < 2200 ? year : null;
}
