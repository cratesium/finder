import 'package:flutter/material.dart';

import '../core/errors/app_error.dart';
import '../core/theme/app_palette.dart';
import 'app_card.dart';

/// Centered illustration-free empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xxxl, horizontal: Gap.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(Gap.radiusLg),
                  border: Border.all(color: c.border),
                ),
                child: Icon(icon, size: 24, color: c.textSecondary),
              ),
              const SizedBox(height: Gap.lg),
              Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: Gap.xs),
                Text(message!,
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(color: c.textSecondary)),
              ],
              if (action != null) ...[const SizedBox(height: Gap.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline banner for errors, warnings and information.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = BannerTone.info,
    this.action,
  });

  factory InlineBanner.error(AppError e, {Widget? action}) =>
      InlineBanner(title: e.title, message: e.message, tone: BannerTone.danger, action: action);

  final String? title;
  final String message;
  final BannerTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final (color, icon) = switch (tone) {
      BannerTone.info => (c.accent, Icons.info_outline_rounded),
      BannerTone.warning => (c.warning, Icons.warning_amber_rounded),
      BannerTone.danger => (c.danger, Icons.error_outline_rounded),
      BannerTone.success => (c.success, Icons.check_circle_outline_rounded),
    };
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      color: color.withValues(alpha: 0.07),
      borderColor: color.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!, style: context.text.titleSmall?.copyWith(color: c.textPrimary)),
                if (title != null) const SizedBox(height: 2),
                Text(message, style: context.text.bodyMedium?.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: Gap.md), action!],
        ],
      ),
    );
  }
}

enum BannerTone { info, warning, danger, success }

/// Network thumbnail with a neutral placeholder and graceful failure.
class MediaThumbnail extends StatelessWidget {
  const MediaThumbnail({super.key, required this.url, this.width = 112, this.height = 63, this.radius = 6});

  final String? url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final placeholder = Container(
      color: c.surfaceHover,
      alignment: Alignment.center,
      child: Icon(Icons.movie_outlined, size: height * 0.35, color: c.textTertiary),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url == null
            ? placeholder
            : Image.network(
                url!,
                fit: BoxFit.cover,
                cacheWidth: (width * 2).round(),
                errorBuilder: (_, _, _) => placeholder,
                frameBuilder: (_, child, frame, sync) =>
                    sync || frame != null ? child : placeholder,
              ),
      ),
    );
  }
}

/// A labeled row used in Settings and option panels.
class FieldRow extends StatelessWidget {
  const FieldRow({super.key, required this.label, this.description, required this.child});

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 560;
      final labelCol = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.titleSmall),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(description!, style: context.text.bodySmall),
          ],
        ],
      );
      if (narrow) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelCol, const SizedBox(height: Gap.sm), child],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: Row(
          children: [
            Expanded(flex: 5, child: labelCol),
            const SizedBox(width: Gap.xl),
            Expanded(flex: 6, child: Align(alignment: Alignment.centerRight, child: child)),
          ],
        ),
      );
    });
  }
}

/// Compact dropdown with consistent styling.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelOf,
    this.isEnabled,
    this.disabledSuffix = ' — not available',
    this.width = 240,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T>? onChanged;
  final String Function(T) labelOf;
  final bool Function(T)? isEnabled;
  final String disabledSuffix;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(Gap.radiusSm + 2),
          border: Border.all(color: c.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: false,
            itemHeight: 48,
            dropdownColor: c.surfaceRaised,
            borderRadius: BorderRadius.circular(Gap.radiusMd),
            focusColor: Colors.transparent,
            icon: Icon(Icons.expand_more_rounded, size: 18, color: c.textSecondary),
            style: context.text.bodyMedium,
            items: [
              for (final item in items)
                DropdownMenuItem<T>(
                  value: item,
                  enabled: isEnabled?.call(item) ?? true,
                  child: Text(
                    (isEnabled?.call(item) ?? true)
                        ? labelOf(item)
                        : '${labelOf(item)}$disabledSuffix',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (isEnabled?.call(item) ?? true) ? c.textPrimary : c.textTertiary,
                    ),
                  ),
                ),
            ],
            onChanged: onChanged == null
                ? null
                : (v) {
                    if (v != null) onChanged!(v);
                  },
          ),
        ),
      ),
    );
  }
}
