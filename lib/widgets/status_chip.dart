import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';
import '../models/download_task.dart';
import '../models/history_record.dart';

enum ChipTone { neutral, accent, success, warning, danger }

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.tone = ChipTone.neutral, this.icon});

  factory StatusChip.task(TaskStatus s) => StatusChip(
        label: s.label,
        tone: switch (s) {
          TaskStatus.completed => ChipTone.success,
          TaskStatus.skipped => ChipTone.neutral,
          TaskStatus.failed => ChipTone.danger,
          TaskStatus.cancelled => ChipTone.neutral,
          TaskStatus.paused => ChipTone.warning,
          TaskStatus.queued => ChipTone.neutral,
          _ => ChipTone.accent,
        },
      );

  factory StatusChip.history(HistoryStatus s) => StatusChip(
        label: s.label,
        tone: switch (s) {
          HistoryStatus.completed => ChipTone.success,
          HistoryStatus.failed => ChipTone.danger,
          HistoryStatus.interrupted => ChipTone.warning,
          HistoryStatus.downloading => ChipTone.accent,
          HistoryStatus.cancelled => ChipTone.neutral,
        },
      );

  final String label;
  final ChipTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final color = switch (tone) {
      ChipTone.neutral => c.textSecondary,
      ChipTone.accent => c.accent,
      ChipTone.success => c.success,
      ChipTone.warning => c.warning,
      ChipTone.danger => c.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tone == ChipTone.neutral ? 0.10 : 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
