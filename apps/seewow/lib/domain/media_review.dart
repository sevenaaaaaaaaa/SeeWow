/// 一条评论。
///
/// 「评论」在 1.21.3 之前根本不存在于数据模型里：详情页只有简介和评分，用户看不到
/// 别人怎么说。这里把来源、作者、正文、分值和时间都保留下来，界面才能回答
/// 「这是谁在哪个站说的、打了几分」，而不是把几条字串混成一段。
class MediaReview {
  const MediaReview({
    required this.source,
    required this.author,
    required this.text,
    this.score,
    this.maxScore = 10,
    this.createdAt,
    this.votes,
    this.url,
  });

  /// 来源站点的短名：`douban` / `anilist`。
  final String source;

  /// 作者昵称；站点不返回时为空串，界面显示「匿名」。
  final String author;

  /// 正文，已去掉 HTML 与多余空白。
  final String text;

  /// 这条评论自己的评分；没有就是 null，绝不补 0。
  final double? score;

  /// [score] 的满分，5 或 10。归一化只在展示层做。
  final double maxScore;

  final DateTime? createdAt;

  /// 有用数 / 得票数，站点不返回时为 null。
  final int? votes;

  final String? url;

  bool get hasScore => score != null && score! > 0;
  bool get isEmpty => text.trim().isEmpty;

  /// 归一到 10 分制，方便和作品评分放在同一条刻度上比较。
  double? get normalizedScore {
    final value = score;
    if (value == null || maxScore <= 0 || value <= 0) return null;
    return value * 10 / maxScore;
  }

  Map<String, dynamic> toJson() => {
    'source': source,
    'author': author,
    'text': text,
    'score': score,
    'maxScore': maxScore,
    'createdAt': createdAt?.toIso8601String(),
    'votes': votes,
    'url': url,
  };

  static MediaReview? fromJson(Object? value) {
    if (value is! Map) return null;
    final text = value['text'];
    if (text is! String || text.trim().isEmpty) return null;
    return MediaReview(
      source: value['source'] as String? ?? '',
      author: value['author'] as String? ?? '',
      text: text,
      score: (value['score'] as num?)?.toDouble(),
      maxScore: (value['maxScore'] as num?)?.toDouble() ?? 10,
      createdAt: DateTime.tryParse(value['createdAt'] as String? ?? ''),
      votes: (value['votes'] as num?)?.toInt(),
      url: value['url'] as String?,
    );
  }
}

/// 一条评论能来自哪个站，界面据此显示站点名。
String reviewSourceLabel(String source) => switch (source) {
  'douban' => '豆瓣',
  'anilist' => 'AniList',
  _ => source,
};
