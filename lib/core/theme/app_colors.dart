import 'package:flutter/material.dart';

/// Base palette of the "glass" look: a deep blue-grey canvas (never pure
/// black), translucent white layers for panels and soft white text tones.
///
/// Colour comes from the blurred artwork behind the UI (see
/// AmbientBackground) and from the user-selectable [Accent].
abstract final class AppColors {
  /// Canvas under the ambient background.
  static const base = Color(0xFF0B0C10);

  /// Opaque surface for overlays that float above content (menus, dialogs,
  /// snack bars) where translucency would hurt legibility.
  static const overlay = Color(0xF21A1C24);

  /// Translucent layers ("glass"), weakest to strongest.
  static const glass = Color(0x0FFFFFFF); // 6 %
  static const glassStrong = Color(0x1AFFFFFF); // 10 %
  static const glassHighlight = Color(0x26FFFFFF); // 15 %
  static const glassBorder = Color(0x1AFFFFFF);

  static const textPrimary = Color(0xFFF5F6FA);
  static const textSecondary = Color(0x9EFFFFFF); // 62 %
  static const textTertiary = Color(0x61FFFFFF); // 38 %

  static const error = Color(0xFFFF6B7D);
}

/// Accent colour, chosen in Settings. Soft, slightly desaturated tones that
/// sit well on top of any artwork. Stored by [name] in settings — renaming a
/// value resets users to the default.
enum Accent {
  sky(Color(0xFF7DB8FF)),
  rose(Color(0xFFFF8FB8)),
  mint(Color(0xFF6FE3B8)),
  lavender(Color(0xFFB59CFF)),
  amber(Color(0xFFFFBE76));

  const Accent(this.color);

  final Color color;

  static Accent fromName(String? name) =>
      Accent.values.firstWhere((a) => a.name == name, orElse: () => Accent.sky);
}
