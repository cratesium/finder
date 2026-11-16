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
    // Phones get tighter gutters and actions below the title.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final gutter = narrow ? Gap.lg : Gap.xxl;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: Gap.xs),
          Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.palette.textSecondary)),
        ],
      ],
    );
    final actionsWrap = Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: actions);
    final header = Padding(
      padding: EdgeInsets.fromLTRB(gutter, narrow ? Gap.lg : Gap.xl, gutter, Gap.lg),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                if (actions.isNotEmpty) ...[const SizedBox(height: Gap.md), actionsWrap],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleBlock),
                if (actions.isNotEmpty) actionsWrap,
              ],
            ),
    );

    final content = Padding(padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter), child: body);

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
                children: [
                  header,
                  Expanded(child: content),
                ],
              ),
      ),
    );
  }
}
