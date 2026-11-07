import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';

/// Bordered surface used for every grouped block of content.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.color,
    this.borderColor,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(Gap.radiusLg),
        border: Border.all(color: borderColor ?? c.border),
        boxShadow: elevated
            ? [BoxShadow(color: c.shadow, blurRadius: 24, offset: const Offset(0, 8))]
            : null,
      ),
      padding: padding,
      child: child,
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
