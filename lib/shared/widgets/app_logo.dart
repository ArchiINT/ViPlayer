import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// "VI" wordmark: white with an accent-tinted second letter.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final style = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: size * 1.4,
      fontWeight: FontWeight.w900,
      letterSpacing: 1,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'V',
            style: style.copyWith(color: AppColors.textPrimary),
          ),
          TextSpan(
            text: 'I',
            style: style.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}
