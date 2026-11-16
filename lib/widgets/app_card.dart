import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';
import '../core/theme/app_theme.dart';

/// White floating card used for every grouped block of content.
///
/// Cards are always bright, whatever the app theme, so everything inside is
/// themed with [AppPalette.card] (dark text, indigo accents). Callers that
/// pass [color] / [borderColor] should derive them from [AppPalette.card].
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.color,
    this.borderColor,
    this.elevated = false,
    this.radius = Gap.radiusCard,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final bool elevated;
  final double radius;

  @override
  Widget build(BuildContext context) {
    const c = AppPalette.card;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!),
    );
    return Theme(
      data: AppTheme.card(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          // Tinted/nested cards (explicit color) sit flat inside their parent.
          boxShadow: [
            if (color == null || elevated)
              BoxShadow(
                color: const Color(0xFF05061E).withValues(alpha: elevated ? 0.28 : 0.16),
                blurRadius: elevated ? 40 : 24,
                offset: Offset(0, elevated ? 16 : 8),
              ),
          ],
        ),
        child: Material(
          color: color ?? c.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Small uppercase heading above a group of controls.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: context.text.labelSmall)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Large card heading ("Expenses", "Transactions") with an optional trailing
/// value or action.
class CardHeader extends StatelessWidget {
  const CardHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.text.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.5),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Builds [builder] under the card theme, so `context.palette` and
/// `context.text` resolve to the white-card palette. Use it in widgets whose
/// `build` creates an [AppCard] and styles the card's content directly.
class CardScope extends StatelessWidget {
  const CardScope({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.card(),
    child: Builder(builder: builder),
  );
}
