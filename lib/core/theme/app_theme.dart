import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Font families bundled in `assets/fonts` (declared in pubspec.yaml).
abstract final class AppFonts {
  /// Main UI text (Latin + Cyrillic).
  static const ui = 'Inter';

  /// Numbers that should not jitter: durations, counters.
  static const mono = 'JetBrainsMono';

  /// Logo only — the font has no Cyrillic glyphs.
  static const display = 'Orbitron';
}

/// Shared motion values so every animation in the app feels the same.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;
}

/// Corner radii — glass panels are softly rounded.
abstract final class AppRadius {
  static const small = 8.0;
  static const medium = 14.0;
  static const large = 20.0;

  static const pill = StadiumBorder();
}

/// Builds the glass theme around the chosen [accent].
///
/// Scaffolds and app bars are transparent: the ambient (blurred artwork)
/// background drawn by the app shell shows through every screen.
abstract final class AppTheme {
  static ThemeData dark(Accent accent) {
    final tint = accent.color;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: tint,
          brightness: Brightness.dark,
        ).copyWith(
          primary: tint,
          onPrimary: AppColors.base,
          secondary: tint,
          onSecondary: AppColors.base,
          surface: AppColors.base,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
          surfaceContainerLowest: AppColors.base,
          surfaceContainerLow: AppColors.overlay,
          surfaceContainer: AppColors.overlay,
          surfaceContainerHigh: AppColors.overlay,
          surfaceContainerHighest: AppColors.overlay,
          outline: AppColors.glassBorder,
          outlineVariant: AppColors.glassBorder,
          error: AppColors.error,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppFonts.ui,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: AppColors.base,
      // Plain ripples: calm, and cheaper than the sparkle shader.
      splashFactory: InkRipple.splashFactory,
      highlightColor: AppColors.glass,
      hoverColor: AppColors.glass,
      splashColor: AppColors.glassStrong,
    );

    const overlayShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.large)),
      side: BorderSide(color: AppColors.glassBorder),
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.textPrimary,
            ),
            headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: AppColors.textPrimary,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.glass,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.medium)),
          side: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.glassBorder,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.medium)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicator: ShapeDecoration(
          color: AppColors.glassHighlight,
          shape: AppRadius.pill,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelPadding: EdgeInsets.symmetric(horizontal: 18),
        labelStyle: TextStyle(
          fontFamily: AppFonts.ui,
          fontWeight: FontWeight.w600,
        ),
        splashBorderRadius: BorderRadius.all(Radius.circular(40)),
        overlayColor: WidgetStatePropertyAll(AppColors.glass),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.glassHighlight,
        indicatorShape: AppRadius.pill,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.textTertiary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? tint
                : AppColors.textSecondary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.glassHighlight,
        indicatorShape: AppRadius.pill,
        selectedIconTheme: IconThemeData(color: tint),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.textSecondary,
        ),
        selectedLabelTextStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textTertiary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tint,
          foregroundColor: AppColors.base,
          shape: AppRadius.pill,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.glass,
          side: const BorderSide(color: AppColors.glassBorder),
          shape: AppRadius.pill,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: tint),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.glass,
          selectedBackgroundColor: AppColors.glassHighlight,
          foregroundColor: AppColors.textSecondary,
          selectedForegroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassStrong,
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.medium)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.medium)),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadius.medium),
          ),
          borderSide: BorderSide(color: tint.withValues(alpha: 0.7)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.overlay,
        shape: overlayShape,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.overlay,
        shape: overlayShape,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.overlay,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        actionTextColor: tint,
        behavior: SnackBarBehavior.floating,
        shape: overlayShape,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tint,
        foregroundColor: AppColors.base,
        elevation: 2,
        shape: AppRadius.pill,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: tint,
        inactiveTrackColor: AppColors.glassStrong,
        thumbColor: AppColors.textPrimary,
        overlayColor: tint.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tint,
        linearTrackColor: AppColors.glassStrong,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.base
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? tint : AppColors.glass,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.glassBorder),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _GlassPageTransitionsBuilder(),
          TargetPlatform.linux: _GlassPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Cross-fade with a short upward drift. Pages are transparent (the ambient
/// background shows through), so the outgoing page must fade out as well —
/// stock transitions assume opaque pages and would show both at once.
class _GlassPageTransitionsBuilder extends PageTransitionsBuilder {
  const _GlassPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.normal;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.curve,
    );
    return FadeTransition(
      opacity: ReverseAnimation(outgoing),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(incoming),
          child: child,
        ),
      ),
    );
  }
}
