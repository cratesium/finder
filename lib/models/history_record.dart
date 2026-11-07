import 'download_options.dart';

enum HistoryStatus {
  downloading('In progress'),
  completed('Completed'),
  failed('Failed'),
  cancelled('Cancelled'),
  interrupted('Interrupted');

  const HistoryStatus(this.label);
  final String label;

  static HistoryStatus fromName(String? name) => values
      .firstWhere((v) => v.name == name, orElse: () => HistoryStatus.failed);
}

/// A persisted download record.
class HistoryRecord {
  const HistoryRecord({
    this.id,
    required this.dedupeKey,
    required this.videoId,
    required this.extractor,
    required this.title,
    required this.url,
    required this.destinationDir,
    required this.status,
    required this.createdAt,
    required this.options,
    this.playlistTitle,
    this.playlistIndex,
    this.thumbnailUrl,
    this.completedAt,
    this.resolution,
    this.format,
    this.fileSize,
    this.filePath,
    this.errorMessage,
    this.fileMissing = false,
  });

  final int? id;
  final String dedupeKey;
  final String videoId;
  final String extractor;
  final String title;
  final String url;
  final String? playlistTitle;
  final int? playlistIndex;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? resolution;
  final String? format;
  final int? fileSize;
  final String? filePath;
  final String destinationDir;
  final HistoryStatus status;
  final String? errorMessage;
  final DownloadOptions options;

  /// Not persisted: computed by checking the filesystem.
  final bool fileMissing;

  DateTime get date => completedAt ?? createdAt;

  HistoryRecord copyWith({
    int? id,
    HistoryStatus? status,
    DateTime? completedAt,
    String? resolution,
    String? format,
    int? fileSize,
    String? filePath,
    String? errorMessage,
    bool clearError = false,
    bool? fileMissing,
  }) =>
      HistoryRecord(
        id: id ?? this.id,
        dedupeKey: dedupeKey,
        videoId: videoId,
        extractor: extractor,
        title: title,
        url: url,
        playlistTitle: playlistTitle,
        playlistIndex: playlistIndex,
        thumbnailUrl: thumbnailUrl,
        createdAt: createdAt,
        destinationDir: destinationDir,
        options: options,
        status: status ?? this.status,
        completedAt: completedAt ?? this.completedAt,
        resolution: resolution ?? this.resolution,
        format: format ?? this.format,
        fileSize: fileSize ?? this.fileSize,
        filePath: filePath ?? this.filePath,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        fileMissing: fileMissing ?? this.fileMissing,
      );
}

enum HistoryDateFilter {
  all('All time'),
  today('Today'),
  week('Last 7 days'),
  month('Last 30 days'),
  custom('Custom range');

  const HistoryDateFilter(this.label);
  final String label;
}

/// Query parameters for the history list.
class HistoryQuery {
  const HistoryQuery({
    this.search = '',
    this.status,
    this.from,
    this.to,
  });

  final String search;
  final HistoryStatus? status;
  final DateTime? from;
  final DateTime? to;
}
