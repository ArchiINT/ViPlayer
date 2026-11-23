import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/update/update_providers.dart';
import '../../core/update/update_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/glass_panel.dart';

/// App update from the paired PC, above the mini player: download progress,
/// then "Install". Takes no space when there is nothing to show.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateStateProvider);
    final visible =
        state.phase != UpdatePhase.none && state.phase != UpdatePhase.failed;
    return AnimatedSize(
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      alignment: Alignment.bottomCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: GlassPanel(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: _content(context, ref, state),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, UpdateState state) {
    final l10n = AppLocalizations.of(context);
    final version = state.offer?.versionName ?? '';
    final accent = Theme.of(context).colorScheme.primary;
    if (state.phase == UpdatePhase.downloading) {
      return Padding(
        padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.updateDownloading(version),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Icon(Icons.system_update_rounded, color: accent, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.updateReady(version),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: () => _install(context, ref),
          child: Text(l10n.updateInstall),
        ),
      ],
    );
  }

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final service = ref.read(updateServiceProvider);
    if (service == null) return;
    final result = await service.install();
    final message = switch (result) {
      InstallResult.started => null,
      InstallResult.needsPermission => l10n.updateNeedsPermission,
      InstallResult.failed => l10n.updateInstallFailed,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
