import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Material 3 theme customized for a dense, professional desktop UI.
abstract final class AppTheme {
  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);
  static ThemeData light() => _build(Brightness.light, AppPalette.light);

  static ThemeData _build(Brightness brightness, AppPalette c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentMuted,
      onPrimaryContainer: c.accent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceHover,
      outline: c.borderStrong,
      outlineVariant: c.border,
      shadow: c.shadow,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.compact,
    );

    final text = base.textTheme.apply(
      bodyColor: c.textPrimary,
      displayColor: c.textPrimary,
    );
    final textTheme = text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
          fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.2),
      titleLarge: text.titleLarge?.copyWith(
          fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(
          fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: -0.1),
      titleSmall: text.titleSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 14, height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 13, height: 1.45),
      bodySmall: text.bodySmall?.copyWith(
          fontSize: 12, height: 1.4, color: c.textSecondary),
      labelLarge: text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: text.labelMedium?.copyWith(
          fontSize: 12, fontWeight: FontWeight.w500, color: c.textSecondary),
      labelSmall: text.labelSmall?.copyWith(
          fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: c.textTertiary),
    );

    final radius = BorderRadius.circular(Gap.radiusSm + 2);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    const buttonMinSize = Size(0, 38);

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: textTheme,
      extensions: [c],
      dividerColor: c.border,
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      splashFactory: InkSparkle.splashFactory,
      hoverColor: c.surfaceHover.withValues(alpha: 0.6),
      focusColor: c.accentMuted,
      iconTheme: IconThemeData(color: c.textSecondary, size: 18),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: c.surfaceHover,
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          border: Border.all(color: c.borderStrong),
        ),
        textStyle: TextStyle(color: c.textPrimary, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.surfaceHover,
          disabledForegroundColor: c.textTertiary,
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.borderStrong),
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          hoverColor: c.surfaceHover,
          minimumSize: const Size(32, 32),
          padding: const EdgeInsets.all(6),
          iconSize: 18,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gap.radiusSm)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceRaised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: TextStyle(color: c.textTertiary, fontSize: 13.5),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 13),
        prefixIconColor: c.textTertiary,
        suffixIconColor: c.textSecondary,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: radius, borderSide: BorderSide(color: c.accent, width: 1.4)),
        errorBorder:
            OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.danger)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: radius, borderSide: BorderSide(color: c.danger, width: 1.4)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
          side: WidgetStatePropertyAll(BorderSide(color: c.borderStrong)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gap.radiusMd),
          side: BorderSide(color: c.borderStrong),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: c.borderStrong)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Gap.radiusMd))),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: c.borderStrong, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onAccent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.onAccent : c.textSecondary),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceHover),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.accent : c.borderStrong),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          side: WidgetStatePropertyAll(BorderSide(color: c.borderStrong)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.accentMuted : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.accent : c.textSecondary),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.surfaceHover,
        thumbColor: c.accent,
        overlayColor: c.accentMuted,
        trackHeight: 3,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceHover,
        circularTrackColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceHover,
        contentTextStyle: TextStyle(color: c.textPrimary, fontSize: 13),
        actionTextColor: c.accent,
        width: 480,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gap.radiusMd),
          side: BorderSide(color: c.borderStrong),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gap.radiusLg),
          side: BorderSide(color: c.border),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.borderStrong),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        dense: true,
      ),
    );
  }
}
