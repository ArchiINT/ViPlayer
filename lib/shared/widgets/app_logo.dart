import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// "VIPLAYER" wordmark with a soft neon glow in the current accent color.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    final neon = Theme.of(context).colorScheme.primary;
    return Text(
      'VI',
      style: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: size * 1.4,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        color: neon,
        shadows: [
          Shadow(color: neon.withValues(alpha: 0.7), blurRadius: size * 0.6),
        ],
      ),
    );
  }
}
