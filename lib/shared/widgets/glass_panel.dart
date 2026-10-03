import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Translucent rounded panel with a hairline border — the basic "glass"
/// surface. Deliberately no BackdropFilter: the background it sits on is
/// already blurred (see AmbientBackground), so a live blur would add GPU cost
/// without a visible difference.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = AppRadius.large,
    this.strong = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Slightly more opaque — for navigation and other chrome.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    // A Material (not a DecoratedBox) so ink ripples of tiles inside stay
    // visible. Clipping keeps ripples inside the rounded corners; panels are
    // few and never inside long lists, so the clip is cheap.
    return Material(
      color: strong ? AppColors.glassStrong : AppColors.glass,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A glass card holding a group of rows (settings, folders), with hairline
/// separators between list tiles.
class GlassGroup extends StatelessWidget {
  const GlassGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && children[i] is ListTile)
              const Divider(indent: 56, endIndent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}
