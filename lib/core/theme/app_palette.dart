import 'package:flutter/material.dart';

/// Finder design tokens. Accessed via `context.palette`.
///
/// "Aurora" look: pages sit on a deep indigo/violet gradient backdrop with
/// soft light beams; grouped content floats on bright white cards. Three
/// palettes exist:
///  * [dark]  — content placed directly on the night backdrop (white text,
///              frosted-glass controls).
///  * [light] — content placed directly on the daylight backdrop.
///  * [card]  — content inside an [AppCard] (always white, in both modes).
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
    required this.accentAlt,
    required this.onAccent,
    required this.brandStart,
    required this.brandMid,
    required this.brandEnd,
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
    required this.glow,
    required this.backdropTop,
    required this.backdropMid,
    required this.backdropBottom,
    required this.beam,
  });

  final Color background;
  final Color sidebar;

  /// Opaque surface (cards, dialogs, menus).
  final Color surface;

  /// Raised / input surface. Frosted glass when placed on the backdrop.
  final Color surfaceRaised;
  final Color surfaceHover;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Primary interactive colour.
  final Color accent;
  final Color accentHover;
  final Color accentMuted;

  /// Secondary accent.
  final Color accentAlt;
  final Color onAccent;

  /// Primary-action gradient stops.
  final Color brandStart;
  final Color brandMid;
  final Color brandEnd;

  final Color info;
  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;

  /// Soft shadow for primary actions.
  final Color glow;

  /// Page backdrop gradient stops and the colour of its light beams.
  final Color backdropTop;
  final Color backdropMid;
  final Color backdropBottom;
  final Color beam;

  /// Primary gradient for main actions, selection and progress.
  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandStart, brandMid, brandEnd],
    stops: const [0, 0.5, 1],
  );

  /// Horizontal variant used for progress bars and indicators.
  LinearGradient get brandGradientHorizontal => LinearGradient(colors: [brandStart, brandEnd]);

  /// Full-page backdrop gradient.
  LinearGradient get backdropGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [backdropTop, backdropMid, backdropBottom],
    stops: const [0, 0.45, 1],
  );

  /// Iridescent orb used for the selected navigation item.
  static const SweepGradient orbGradient = SweepGradient(
    colors: [
      Color(0xFF8EC5FF),
      Color(0xFFF0A6FF),
      Color(0xFFFFD6E8),
      Color(0xFFA6F0FF),
      Color(0xFFB9A6FF),
      Color(0xFF8EC5FF),
    ],
  );

  /// Categorical chart colours (validated for contrast on white cards).
  static const chartColors = [
    Color(0xFF2F5BFF), // blue
    Color(0xFFA77BFA), // violet
    Color(0xFF3FD07A), // green
    Color(0xFFF5B83D), // amber
    Color(0xFFF06FB4), // pink
    Color(0xFF4CC9E8), // cyan
  ];

  static const _indigo = Color(0xFF3B3FE4);

  /// Content on the night backdrop.
  static const dark = AppPalette(
    background: Color(0xFF0A0C33),
    sidebar: Color(0x14FFFFFF),
    surface: Color(0xFF181C55), // opaque: dialogs, menus, snackbars
    surfaceRaised: Color(0x1FFFFFFF), // frosted glass
    surfaceHover: Color(0x2EFFFFFF),
    border: Color(0x2EFFFFFF),
    borderStrong: Color(0x4DFFFFFF),
    textPrimary: Color(0xFFF7F8FF),
    textSecondary: Color(0xFFB9BDE8),
    textTertiary: Color(0xFF8D92C4),
    accent: Color(0xFFFFFFFF),
    accentHover: Color(0xFFFFFFFF),
    accentMuted: Color(0x26FFFFFF),
    accentAlt: Color(0xFFC9CDFF),
    onAccent: Color(0xFF151A5C),
    brandStart: Color(0xFFFFFFFF),
    brandMid: Color(0xFFF1F2FF),
    brandEnd: Color(0xFFDCDFFF),
    info: Color(0xFFA9B6FF),
    success: Color(0xFF5BE08F),
    warning: Color(0xFFFFC857),
    danger: Color(0xFFFF7D7D),
    shadow: Color(0x66000016),
    glow: Color(0x55000016),
    backdropTop: Color(0xFF0B0E4A),
    backdropMid: Color(0xFF1B1F8C),
    backdropBottom: Color(0xFF080A26),
    beam: Color(0xFF9C8CFF),
  );

  /// Content on the daylight backdrop.
  static const light = AppPalette(
    background: Color(0xFFECEEFF),
    sidebar: Color(0x8CFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xCCFFFFFF),
    surfaceHover: Color(0xFFF1F2FB),
    border: Color(0x1F1E2470),
    borderStrong: Color(0x331E2470),
    textPrimary: Color(0xFF0F1238),
    textSecondary: Color(0xFF4F5478),
    textTertiary: Color(0xFF7E83A6),
    accent: _indigo,
    accentHover: Color(0xFF2E32C9),
    accentMuted: Color(0x1A3B3FE4),
    accentAlt: Color(0xFF6D4CF2),
    onAccent: Color(0xFFFFFFFF),
    brandStart: Color(0xFF3D5AFE),
    brandMid: Color(0xFF4F3FE8),
    brandEnd: Color(0xFF7C4DFF),
    info: Color(0xFF4F6BFF),
    success: Color(0xFF15924A),
    warning: Color(0xFFB45F06),
    danger: Color(0xFFD12C2C),
    shadow: Color(0x1F1A1F6B),
    glow: Color(0x403B3FE4),
    backdropTop: Color(0xFFDDE2FF),
    backdropMid: Color(0xFFEDE6FF),
    backdropBottom: Color(0xFFE3EEFF),
    beam: Color(0xFFFFFFFF),
  );

  /// Content inside white cards (both modes).
  static const card = AppPalette(
    background: Color(0xFFF4F5FB),
    sidebar: Color(0xFFF4F5FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF4F5FB),
    surfaceHover: Color(0xFFEBEDF7),
    border: Color(0xFFE8E9F3),
    borderStrong: Color(0xFFD3D6E8),
    textPrimary: Color(0xFF0F1238),
    textSecondary: Color(0xFF5A5E7E),
    textTertiary: Color(0xFF9296B3),
    accent: _indigo,
    accentHover: Color(0xFF2E32C9),
    accentMuted: Color(0x173B3FE4),
    accentAlt: Color(0xFF6D4CF2),
    onAccent: Color(0xFFFFFFFF),
    brandStart: Color(0xFF3D5AFE),
    brandMid: Color(0xFF4F3FE8),
    brandEnd: Color(0xFF7C4DFF),
    info: Color(0xFF4F6BFF),
    success: Color(0xFF15924A),
    warning: Color(0xFFB45F06),
    danger: Color(0xFFD12C2C),
    shadow: Color(0x1F1A1F6B),
    glow: Color(0x403B3FE4),
    backdropTop: Color(0xFFFFFFFF),
    backdropMid: Color(0xFFFFFFFF),
    backdropBottom: Color(0xFFFFFFFF),
    beam: Color(0xFFFFFFFF),
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
      accentAlt: l(accentAlt, other.accentAlt),
      onAccent: l(onAccent, other.onAccent),
      brandStart: l(brandStart, other.brandStart),
      brandMid: l(brandMid, other.brandMid),
      brandEnd: l(brandEnd, other.brandEnd),
      info: l(info, other.info),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      shadow: l(shadow, other.shadow),
      glow: l(glow, other.glow),
      backdropTop: l(backdropTop, other.backdropTop),
      backdropMid: l(backdropMid, other.backdropMid),
      backdropBottom: l(backdropBottom, other.backdropBottom),
      beam: l(beam, other.beam),
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

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusXl = 22.0;
  static const radiusCard = 28.0;
}

/// Motion tokens. Durations are long enough to read as motion rather than a
/// jump; curves ease out softly so nothing stops abruptly.
abstract final class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);

  /// State changes (size, colour, position).
  static const curve = Curves.easeInOutCubicEmphasized;

  /// Content entering the screen.
  static const enter = Curves.easeOutQuart;

  /// Content leaving the screen.
  static const exit = Curves.easeInCubic;
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
  TextTheme get text => Theme.of(this).textTheme;
}
