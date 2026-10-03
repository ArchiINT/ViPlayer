import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/library/library_providers.dart';
import '../../../core/library/library_scanner.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Thin neon progress line + status text, visible only while scanning.
class ScanStatusBar extends ConsumerWidget {
  const ScanStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    final l10n = AppLocalizations.of(context);
    final progress = scan.progress;

    final String? label = switch (progress?.phase) {
      _ when !scan.running => null,
      ScanPhase.discovering || null => l10n.scanDiscovering,
      ScanPhase.reading when progress!.total > 0 => l10n.scanReading(
        progress.done,
        progress.total,
      ),
      ScanPhase.reading => l10n.scanDiscovering,
      ScanPhase.saving => l10n.scanSaving,
    };

    return AnimatedSize(
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: label == null
          ? const SizedBox(width: double.infinity)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: progress?.phase == ScanPhase.reading
                      ? progress?.fraction
                      : null,
                  minHeight: 2,
                ),
                ColoredBox(
                  color: AppColors.overlay,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
