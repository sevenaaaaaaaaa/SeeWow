enum DownloadStatus { queued, downloading, paused, completed, failed }

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.itemId,
    required this.title,
    required this.sourceName,
    this.sourceId = '',
    this.quality = '原始画质',
    this.filePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.queued,
    this.error,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id, itemId, title, sourceName, sourceId;
  final String quality;
  final DateTime createdAt;
  String? filePath;
  int totalBytes;
  int downloadedBytes;
  DownloadStatus status;
  String? error;
  DateTime updatedAt;

  double get progress {
    if (status == DownloadStatus.completed) return 1;
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0, 1);
  }

  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;
  bool get isDone => status == DownloadStatus.completed;
  bool get isPaused => status == DownloadStatus.paused;
  bool get isFailed => status == DownloadStatus.failed;

  String get statusLabel => switch (status) {
    DownloadStatus.queued => '等待中',
    DownloadStatus.downloading => '缓存中',
    DownloadStatus.paused => '已暂停',
    DownloadStatus.completed => '已离线',
    DownloadStatus.failed => '失败',
  };

  String get sizeLabel {
    if (totalBytes <= 0) return '计算中';
    final mb = totalBytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'itemId': itemId,
    'title': title,
    'sourceName': sourceName,
    'sourceId': sourceId,
    'quality': quality,
    'filePath': filePath,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'status': status.name,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static DownloadTask fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String? ?? 'queued';
    final status = DownloadStatus.values.firstWhere(
      (value) => value.name == rawStatus,
      orElse: () => DownloadStatus.paused,
    );
    return DownloadTask(
      id: json['id'] as String? ?? '',
      itemId: json['itemId'] as String? ?? '',
      title: json['title'] as String? ?? '未命名',
      sourceName: json['sourceName'] as String? ?? '未知来源',
      sourceId: json['sourceId'] as String? ?? '',
      quality: json['quality'] as String? ?? '原始画质',
      filePath: json['filePath'] as String?,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      status: status,
      error: json['error'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}
