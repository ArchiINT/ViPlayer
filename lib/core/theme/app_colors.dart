import 'package:flutter/material.dart';

/// The fixed (non-accent) palette: pure black base for OLED screens, a few
/// near-black surface steps for depth, and muted text tones.
///
/// Accent colors are user-selectable — see [NeonAccent].
abstract final class AppColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF0A0A0F);
  static const surfaceRaised = Color(0xFF12121A);
  static const surfaceHighest = Color(0xFF1A1A24);
  static const outline = Color(0xFF23232F);

  static const textPrimary = Color(0xFFEDEDF2);
  static const textSecondary = Color(0xFF8A8A9A);
  static const textDisabled = Color(0xFF4A4A58);

  static const error = Color(0xFFFF3B5C);
}

/// Neon accent the whole UI is tinted with. Stored in settings by [name], so
/// renaming a value is a breaking change for saved preferences.
enum NeonAccent {
  cyan(Color(0xFF00F0FF)),
  magenta(Color(0xFFFF2A6D)),
  acid(Color(0xFFC6FF00)),
  violet(Color(0xFFA259FF));

  const NeonAccent(this.color);

  final Color color;

  static NeonAccent fromName(String? name) => NeonAccent.values.firstWhere(
    (a) => a.name == name,
    orElse: () => NeonAccent.cyan,
  );
}
