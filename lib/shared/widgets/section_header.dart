import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Small monospace, letter-spaced heading used to group settings and lists,
/// e.g. `// APPEARANCE`.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        '// ${title.toUpperCase()}',
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
