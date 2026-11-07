import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';

/// Standard page layout: header with title/subtitle/actions and a body.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.body,
    this.scrollable = true,
    this.maxContentWidth = 1280,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final bool scrollable;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xxl, Gap.xl, Gap.xxl, Gap.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.palette.textSecondary)),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: actions),
        ],
      ),
    );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xxl, 0, Gap.xxl, Gap.xxl),
      child: body,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: scrollable
            ? CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: header),
                  SliverToBoxAdapter(child: content),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, Expanded(child: content)],
              ),
      ),
    );
  }
}
