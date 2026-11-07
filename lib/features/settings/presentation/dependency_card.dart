import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/path_utils.dart';
import '../../../models/dependency_status.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/feedback.dart';
import '../../../widgets/status_chip.dart';
import '../application/dependency_controller.dart';
import '../application/settings_controller.dart';

class DependencyCard extends ConsumerWidget {
  const DependencyCard({super.key, required this.kind});
  final DependencyKind kind;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final path = await ref.read(directoryPickerProvider).pickExecutable();
    if (path == null) return;
    final manager = ref.read(dependencyManagerProvider);
    final status = await manager.validate(kind, path, DependencySource.custom);
    if (!context.mounted) return;
    if (!status.isReady) {
      showToast(context, '${kind.label} rejected: ${status.message}');
      return;
    }
    await ref.read(settingsProvider.notifier).change((s) => kind == DependencyKind.ytDlp
        ? s.copyWith(ytDlpPath: () => path)
        : s.copyWith(ffmpegPath: () => path));
    if (context.mounted) showToast(context, 'Using ${kind.label} ${status.version}.');
  }

  Future<void> _resetToAuto(WidgetRef ref) => ref.read(settingsProvider.notifier).change((s) =>
      kind == DependencyKind.ytDlp ? s.copyWith(ytDlpPath: () => null) : s.copyWith(ffmpegPath: () => null));

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(installProvider.notifier).install(kind);
    if (!context.mounted) return;
    final err = ref.read(installProvider)[kind]?.error;
    showToast(context, ok ? '${kind.label} installed and verified.' : (err?.message ?? 'Installation failed.'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.palette;
    final snapshot = ref.watch(dependencyProvider);
    final install = ref.watch(installProvider)[kind];
    final manager = ref.read(dependencyManagerProvider);
    final settings = ref.watch(settingsProvider);
    final hasCustom = kind == DependencyKind.ytDlp ? settings.ytDlpPath != null : settings.ffmpegPath != null;
    final status = snapshot.value?.of(kind);
    final installing = install?.running ?? false;

    final chip = snapshot.isLoading
        ? const StatusChip(label: 'Checking…')
        : switch (status?.state) {
            DependencyState.ready => const StatusChip(label: 'Ready', tone: ChipTone.success, icon: Icons.check_rounded),
            DependencyState.invalid => const StatusChip(label: 'Invalid', tone: ChipTone.danger),
            _ => const StatusChip(label: 'Missing', tone: ChipTone.warning),
          };

    final canInstall = manager.canInstall(kind);
    final installLabel = status?.isReady == true && status?.source == DependencySource.managed ? 'Update' : 'Install';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(Gap.radiusSm + 2),
                  border: Border.all(color: c.border),
                ),
                child: Icon(kind == DependencyKind.ytDlp ? Icons.download_for_offline_outlined : Icons.movie_filter_outlined,
                    size: 18, color: c.textSecondary),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.label, style: context.text.titleMedium),
                    Text(
                      kind == DependencyKind.ytDlp
                          ? 'Reads metadata and downloads media'
                          : 'Merges streams, extracts and converts audio',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              chip,
            ],
          ),
          const SizedBox(height: Gap.md),
          if (status != null) ...[
            _kv(context, 'Version', status.version ?? '—'),
            _kv(context, 'Source', status.source?.label ?? '—'),
            _kv(context, 'Path', status.path == null ? '—' : PathUtils.displayPath(status.path!), selectable: true),
            if (status.message != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Text(status.message!,
                    style: context.text.bodySmall?.copyWith(
                        color: status.state == DependencyState.ready ? c.warning : c.danger)),
              ),
          ],
          if (status != null && !status.isReady) ...[
            const SizedBox(height: Gap.sm),
            Text(manager.guidance(kind), style: context.text.bodySmall),
          ],
          if (installing) ...[
            const SizedBox(height: Gap.md),
            LinearProgressIndicator(value: install?.fraction, minHeight: 4),
            const SizedBox(height: 4),
            Text(install?.stage ?? 'Working…', style: context.text.labelMedium),
          ],
          if (install?.error != null && !installing) ...[
            const SizedBox(height: Gap.sm),
            Text(install!.error!.message, style: context.text.bodySmall?.copyWith(color: c.danger)),
          ],
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              if (canInstall)
                FilledButton.icon(
                  onPressed: installing ? null : () => _install(context, ref),
                  icon: Icon(installLabel == 'Update' ? Icons.system_update_alt_rounded : Icons.download_rounded, size: 16),
                  label: Text(installLabel),
                ),
              OutlinedButton.icon(
                onPressed: installing ? null : () => _choose(context, ref),
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Choose file…'),
              ),
              if (hasCustom)
                TextButton(onPressed: () => _resetToAuto(ref), child: const Text('Use automatic detection')),
              TextButton(
                onPressed: installing ? null : () => ref.read(dependencyProvider.notifier).recheck(),
                child: const Text('Re-check'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {bool selectable = false}) {
    final style = context.text.bodySmall?.copyWith(color: context.palette.textPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(k, style: context.text.bodySmall)),
          Expanded(child: selectable ? SelectableText(v, style: style) : Text(v, style: style)),
        ],
      ),
    );
  }
}
