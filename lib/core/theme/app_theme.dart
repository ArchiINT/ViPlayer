import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Font families bundled in `assets/fonts` (declared in pubspec.yaml).
abstract final class AppFonts {
  /// Main UI text (Latin + Cyrillic).
  static const ui = 'Inter';

  /// Technical details: durations, bitrates, counters.
  static const mono = 'JetBrainsMono';

  /// Logo only — the font has no Cyrillic glyphs.
  static const display = 'Orbitron';
}

/// Shared motion values so every animation in the app feels the same.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;
}

/// Builds the dark cyberpunk theme around the chosen [accent].
abstract final class AppTheme {
  /// Chamfered corners are the signature shape: cards, buttons and dialogs
  /// use them instead of rounded corners.
  static const chamfer = BeveledRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );

  static ThemeData dark(NeonAccent accent) {
    final neon = accent.color;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: neon,
          brightness: Brightness.dark,
        ).copyWith(
          primary: neon,
          onPrimary: AppColors.background,
          secondary: neon,
          onSecondary: AppColors.background,
          surface: AppColors.background,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
          surfaceContainerLowest: AppColors.background,
          surfaceContainerLow: AppColors.surface,
          surfaceContainer: AppColors.surface,
          surfaceContainerHigh: AppColors.surfaceRaised,
          surfaceContainerHighest: AppColors.surfaceHighest,
          outline: AppColors.outline,
          outlineVariant: AppColors.outline,
          error: AppColors.error,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppFonts.ui,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: AppColors.outline),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        selectedColor: neon,
        selectedTileColor: neon.withValues(alpha: 0.08),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: neon.withValues(alpha: 0.14),
        indicatorShape: chamfer,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: states.contains(WidgetState.selected)
                ? neon
                : AppColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? neon
                : AppColors.textSecondary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: neon.withValues(alpha: 0.14),
        indicatorShape: chamfer,
        selectedIconTheme: IconThemeData(color: neon),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.textSecondary,
        ),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: neon,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: neon,
          foregroundColor: AppColors.background,
          shape: chamfer,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: neon,
          side: BorderSide(color: neon.withValues(alpha: 0.6)),
          shape: chamfer,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: neon),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        border: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.outline),
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: neon, width: 1.5),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        actionTextColor: neon,
        behavior: SnackBarBehavior.floating,
        shape: BeveledRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: neon.withValues(alpha: 0.4)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: neon,
        inactiveTrackColor: AppColors.outline,
        thumbColor: neon,
        overlayColor: neon.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: neon,
        linearTrackColor: AppColors.outline,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.background
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? neon : AppColors.surface,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.outline),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
