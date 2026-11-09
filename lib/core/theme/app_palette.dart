import 'package:flutter/material.dart';

/// Design tokens for finder. Accessed via `context.palette`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentHover,
    required this.accentMuted,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
  });

  final Color background;
  final Color sidebar;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHover;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentHover;
  final Color accentMuted;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;

  static const dark = AppPalette(
    background: Color(0xFF0B0C0E),
    sidebar: Color(0xFF0F1013),
    surface: Color(0xFF15171A),
    surfaceRaised: Color(0xFF1B1E22),
    surfaceHover: Color(0xFF22262B),
    border: Color(0xFF262A30),
    borderStrong: Color(0xFF363B42),
    textPrimary: Color(0xFFECEEF1),
    textSecondary: Color(0xFFA0A6AF),
    textTertiary: Color(0xFF6A707A),
    accent: Color(0xFF3B82F6),
    accentHover: Color(0xFF5B97F8),
    accentMuted: Color(0x263B82F6),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF2A93B),
    danger: Color(0xFFEF5350),
    shadow: Color(0x66000000),
  );

  static const light = AppPalette(
    background: Color(0xFFF5F6F8),
    sidebar: Color(0xFFEDEFF2),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF8F9FA),
    surfaceHover: Color(0xFFF0F2F5),
    border: Color(0xFFE1E4E9),
    borderStrong: Color(0xFFC9CED6),
    textPrimary: Color(0xFF111418),
    textSecondary: Color(0xFF545C67),
    textTertiary: Color(0xFF8A919B),
    accent: Color(0xFF2563EB),
    accentHover: Color(0xFF1D4FD8),
    accentMuted: Color(0x1F2563EB),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    shadow: Color(0x1A0F172A),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      sidebar: l(sidebar, other.sidebar),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      accent: l(accent, other.accent),
      accentHover: l(accentHover, other.accentHover),
      accentMuted: l(accentMuted, other.accentMuted),
      onAccent: l(onAccent, other.onAccent),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// Spacing scale (4pt grid) and radii.
abstract final class Gap {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  static const radiusSm = 6.0;
  static const radiusMd = 10.0;
  static const radiusLg = 14.0;
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
  TextTheme get text => Theme.of(this).textTheme;
}
