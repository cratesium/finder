import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/path_utils.dart';
import '../../../models/download_task.dart';
import '../../../models/history_record.dart';
import '../../../models/media_info.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/common.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/page_scaffold.dart';
import '../../../widgets/status_chip.dart';
import '../../downloads/application/download_providers.dart';
import '../application/history_controller.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _search =
      TextEditingController(text: ref.read(historyFilterProvider).search);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _setFilter(HistoryFilter f) => ref.read(historyFilterProvider.notifier).set(f);

  Future<void> _pickDate(HistoryFilter filter, HistoryDateFilter choice) async {
    if (choice != HistoryDateFilter.custom) {
      _setFilter(filter.copyWith(date: choice, customRange: () => null));
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: filter.customRange,
    );
    if (range != null) _setFilter(filter.copyWith(date: choice, customRange: () => range));
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(historyFilterProvider);
    final history = ref.watch(historyProvider);

    return PageScaffold(
      title: 'History',
      subtitle: 'Every download is recorded locally on this computer.',
      actions: [
        OutlinedButton.icon(
          onPressed: (history.value?.isEmpty ?? true)
              ? null
              : () async {
                  final ok = await confirmDialog(context,
                      title: 'Clear download history?',
                      message: 'All history records will be removed. Downloaded files are not deleted.',
                      confirmLabel: 'Clear history',
                      destructive: true);
                  if (!ok) return;
                  try {
                    await ref.read(historyRepositoryProvider).clear();
                  } catch (e) {
                    if (context.mounted) showErrorToast(context, e);
                  }
                  ref.read(historyRevisionProvider.notifier).bump();
                },
          icon: const Icon(Icons.delete_sweep_outlined, size: 17),
          label: const Text('Clear history'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  key: const Key('history-search'),
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Search title, playlist, URL or ID',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250),
                        () => _setFilter(ref.read(historyFilterProvider).copyWith(search: v)));
                  },
                ),
              ),
              AppDropdown<HistoryStatus?>(
                width: 180,
                value: filter.status,
                items: const [null, ...HistoryStatus.values],
                labelOf: (s) => s == null ? 'All statuses' : s.label,
                onChanged: (s) => _setFilter(filter.copyWith(status: () => s)),
              ),
              AppDropdown<HistoryDateFilter>(
                width: 180,
                value: filter.date,
                items: HistoryDateFilter.values,
                labelOf: (d) => d == HistoryDateFilter.custom && filter.customRange != null
                    ? '${Fmt.date(filter.customRange!.start)} – ${Fmt.date(filter.customRange!.end)}'
                    : d.label,
                onChanged: (d) => _pickDate(filter, d),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          history.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Gap.xxl),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => InlineBanner.error(
              e is AppError ? e : AppError.of(AppErrorKind.storage),
              action: TextButton(
                onPressed: () => ref.read(historyRevisionProvider.notifier).bump(),
                child: const Text('Retry'),
              ),
            ),
            data: (records) => records.isEmpty
                ? AppCard(
                    child: EmptyState(
                      icon: Icons.history_rounded,
                      title: filter.search.isEmpty && filter.status == null && filter.date == HistoryDateFilter.all
                          ? 'No history yet'
                          : 'No matching records',
                      message: 'Finished, failed and cancelled downloads appear here.',
                    ),
                  )
                : _HistoryTable(records: records),
          ),
        ],
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.records});
  final List<HistoryRecord> records;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
            child: Row(
              children: [
                Expanded(flex: 6, child: Text('TITLE', style: context.text.labelSmall)),
                const SizedBox(width: Gap.lg),
                Expanded(flex: 2, child: Text('DATE', style: context.text.labelSmall)),
                Expanded(flex: 2, child: Text('FORMAT', style: context.text.labelSmall)),
                Expanded(flex: 2, child: Text('SIZE', style: context.text.labelSmall)),
                SizedBox(width: 110, child: Text('STATUS', style: context.text.labelSmall)),
                const SizedBox(width: 40),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          for (var i = 0; i < records.length; i++) ...[
            _HistoryRow(record: records[i]),
            if (i != records.length - 1) Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.record});
  final HistoryRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final r = record;
    final opener = ref.read(fileOpenerProvider);
    final canOpen = r.status == HistoryStatus.completed && r.filePath != null && !r.fileMissing;

    Future<void> guard(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        if (context.mounted) showErrorToast(context, e);
      }
    }

    Future<void> downloadAgain() async {
      final request = DownloadRequest(
        entry: MediaEntry(
          id: r.videoId,
          title: r.title,
          url: r.url,
          extractor: r.extractor,
          thumbnailUrl: r.thumbnailUrl,
          playlistIndex: r.playlistIndex,
        ),
        options: r.options,
        playlistTitle: r.playlistTitle,
      );
      final result = await ref.read(downloadManagerProvider).requeue(request);
      if (context.mounted) showToast(context, result.describe());
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Row(
              children: [
                MediaThumbnail(url: r.thumbnailUrl, width: 72, height: 40, radius: 5),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        r.fileMissing
                            ? 'File missing — it was moved or deleted'
                            : (r.errorMessage ?? r.playlistTitle ?? PathUtils.displayPath(r.destinationDir)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                            color: r.fileMissing
                                ? c.warning
                                : (r.errorMessage != null ? c.danger : c.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.lg),
          Expanded(flex: 2, child: Text(Fmt.dateTime(r.date), style: context.text.bodySmall)),
          Expanded(
            flex: 2,
            child: Text(
              [if (r.resolution != null) r.resolution!, if (r.format != null) r.format!.toUpperCase()]
                  .join(' · ')
                  .ifEmpty('—'),
              style: context.text.bodySmall,
            ),
          ),
          Expanded(flex: 2, child: Text(Fmt.bytes(r.fileSize), style: context.text.bodySmall)),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerLeft,
              child: r.fileMissing
                  ? const StatusChip(label: 'Missing', tone: ChipTone.warning)
                  : StatusChip.history(r.status),
            ),
          ),
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              onSelected: (v) async {
                switch (v) {
                  case 'open':
                    await guard(() => opener.openFile(r.filePath!));
                  case 'reveal':
                    await guard(() => opener.revealInFolder(r.filePath!));
                  case 'folder':
                    await guard(() => opener.openFolder(r.destinationDir));
                  case 'again':
                    await guard(downloadAgain);
                  case 'remove':
                    if (r.id != null) {
                      await guard(() => ref.read(historyRepositoryProvider).delete(r.id!));
                      ref.read(historyRevisionProvider.notifier).bump();
                    }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'open', enabled: canOpen, child: const Text('Open file')),
                PopupMenuItem(value: 'reveal', enabled: canOpen, child: const Text('Show in folder')),
                const PopupMenuItem(value: 'folder', child: Text('Open destination folder')),
                if (!canOpen) const PopupMenuItem(value: 'again', child: Text('Retry download')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'remove', child: Text('Remove record')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
