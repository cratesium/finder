import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';

/// The Finder logo mark (same artwork as the app icon).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    // Painted gradient fallback if the asset is unavailable (e.g. in tests).
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: c.brandGradient, borderRadius: BorderRadius.circular(size * 0.24)),
      child: Icon(Icons.move_to_inbox_rounded, size: size * 0.58, color: c.onAccent),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [BoxShadow(color: c.glow, blurRadius: size * 0.45, offset: Offset(0, size * 0.12))],
      ),
      child: Image.asset(
        'assets/icons/logo_256.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// "Finder" word mark with an optional gradient.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 16, this.gradient = false});
  final double fontSize;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final style = context.text.titleMedium?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.02 * fontSize,
    );
    final text = Text('Finder', style: style, overflow: TextOverflow.ellipsis);
    if (!gradient) return text;
    return GradientText(text: 'Finder', style: style);
  }
}

/// Text filled with the brand gradient.
class GradientText extends StatelessWidget {
  const GradientText({super.key, required this.text, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          LinearGradient(colors: [c.brandStart, c.brandEnd]).createShader(Offset.zero & bounds.size),
      child: Text(text, style: style, textAlign: textAlign),
    );
  }
}

/// Primary call-to-action: white on dark, black on light.
///
/// Falls back to a flat, muted look when disabled. Shows a spinner while
/// [loading].
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.height = 44,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double height;
  final bool expand;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final enabled = widget.onPressed != null && !widget.loading;
    final fg = enabled ? c.onAccent : c.textTertiary;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
        else if (widget.icon != null)
          Icon(widget.icon, size: 18, color: fg),
        if (widget.loading || widget.icon != null) const SizedBox(width: Gap.sm),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelLarge?.copyWith(color: fg, fontSize: 13.5, letterSpacing: 0.1),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1,
            duration: Motion.fast,
            child: AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.curve,
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: enabled ? c.brandGradient : null,
                color: enabled ? null : c.surfaceHover,
                borderRadius: BorderRadius.circular(999),
                border: enabled ? null : Border.all(color: c.border),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: c.glow.withValues(alpha: _hover ? 0.55 : 0.32),
                          blurRadius: _hover ? 18 : 12,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              foregroundDecoration: _hover && enabled
                  ? BoxDecoration(color: c.onAccent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(999))
                  : null,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Slim progress bar filled with the brand gradient. [value] null means
/// indeterminate.
class BrandProgressBar extends StatelessWidget {
  const BrandProgressBar({super.key, required this.value, this.height = 6, this.color});

  final double? value;
  final double height;

  /// Solid colour override (e.g. paused / failed states).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    if (value == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(minHeight: height, color: color ?? c.accent, backgroundColor: c.surfaceHover),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final v = value!.clamp(0.0, 1.0);
        return Container(
          height: height,
          decoration: BoxDecoration(color: c.surfaceHover, borderRadius: BorderRadius.circular(height)),
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: v),
            duration: Motion.slow,
            curve: Motion.curve,
            builder: (context, t, _) => Container(
              width: constraints.maxWidth * t,
              decoration: BoxDecoration(
                gradient: color == null ? c.brandGradientHorizontal : null,
                color: color,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pill-style segmented selector used for modes and filters.
class PillSelector<T> extends StatelessWidget {
  const PillSelector({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
    this.countOf,
    this.keyOf,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final IconData? Function(T)? iconOf;
  final int? Function(T)? countOf;
  final Key? Function(T)? keyOf;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final item in items)
            _Pill(
              key: keyOf?.call(item),
              label: labelOf(item),
              icon: iconOf?.call(item),
              count: countOf?.call(item),
              selected: item == value,
              onTap: onChanged == null ? null : () => onChanged!(item),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.selected, this.icon, this.count, this.onTap});
  final String label;
  final bool selected;
  final IconData? icon;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final fg = selected ? c.onAccent : c.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: Motion.medium,
          curve: Motion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected ? c.brandGradient : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(
                label,
                style: context.text.labelLarge?.copyWith(
                  color: selected ? c.onAccent : c.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? c.onAccent.withValues(alpha: 0.15) : c.surfaceHover,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? c.onAccent : c.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
