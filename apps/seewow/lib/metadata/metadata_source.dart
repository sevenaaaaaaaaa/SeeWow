import '../domain/media_metadata.dart';

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
