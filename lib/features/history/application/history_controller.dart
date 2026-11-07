import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../models/history_record.dart';
import '../../downloads/application/download_providers.dart';

class HistoryFilter {
  const HistoryFilter({
    this.search = '',
    this.status,
    this.date = HistoryDateFilter.all,
    this.customRange,
  });

  final String search;
  final HistoryStatus? status;
  final HistoryDateFilter date;
  final DateTimeRange? customRange;

  HistoryQuery toQuery(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final (DateTime? from, DateTime? to) = switch (date) {
      HistoryDateFilter.all => (null, null),
      HistoryDateFilter.today => (today, null),
      HistoryDateFilter.week => (today.subtract(const Duration(days: 6)), null),
      HistoryDateFilter.month => (today.subtract(const Duration(days: 29)), null),
      HistoryDateFilter.custom => (
          customRange?.start,
          customRange == null
              ? null
              : DateTime(customRange!.end.year, customRange!.end.month, customRange!.end.day + 1),
        ),
    };
    return HistoryQuery(search: search, status: status, from: from, to: to);
  }

  HistoryFilter copyWith({
    String? search,
    HistoryStatus? Function()? status,
    HistoryDateFilter? date,
    DateTimeRange? Function()? customRange,
  }) =>
      HistoryFilter(
        search: search ?? this.search,
        status: status != null ? status() : this.status,
        date: date ?? this.date,
        customRange: customRange != null ? customRange() : this.customRange,
      );
}

class HistoryFilterController extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();
  void set(HistoryFilter f) => state = f;
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterController, HistoryFilter>(HistoryFilterController.new);

/// Manual refresh counter (removals, clears).
class HistoryRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final historyRevisionProvider = NotifierProvider<HistoryRevision, int>(HistoryRevision.new);

/// Checks whether completed downloads still exist on disk.
Future<List<HistoryRecord>> markMissingFiles(List<HistoryRecord> records) async {
  return Future.wait(records.map((r) async {
    if (r.status != HistoryStatus.completed || r.filePath == null) return r;
    final exists = await File(r.filePath!).exists();
    return exists ? r : r.copyWith(fileMissing: true);
  }));
}

final historyProvider = FutureProvider<List<HistoryRecord>>((ref) async {
  final filter = ref.watch(historyFilterProvider);
  ref.watch(historyRevisionProvider);
  // Refresh when tasks finish.
  ref.watch(tasksProvider.select((ts) => ts.where((t) => t.status.isTerminal).length));
  final records = await ref.read(historyRepositoryProvider).query(filter.toQuery(DateTime.now()));
  return markMissingFiles(records);
});
