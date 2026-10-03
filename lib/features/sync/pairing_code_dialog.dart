import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Shows the pairing code whenever another device asks to pair — wherever
/// the user is in the app. Closes itself once pairing completes or the code
/// is withdrawn.
class PairingCodeListener extends ConsumerWidget {
  const PairingCodeListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(syncSnapshotProvider.select((s) => s.pendingCode), (
      previous,
      next,
    ) {
      if (next != null && previous == null) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _PairingCodeDialog(),
        );
      }
    });
    return child;
  }
}

class _PairingCodeDialog extends ConsumerWidget {
  const _PairingCodeDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      syncSnapshotProvider.select((s) => s.pendingCode),
    );
    if (pending == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    final code = pending.code;
    return AlertDialog(
      title: Text(l10n.syncCodeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.syncCodeBody(pending.peerName)),
          const SizedBox(height: 20),
          Text(
            '${code.substring(0, 3)} ${code.substring(3)}',
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: ref.read(syncServiceProvider).cancelPairingCode,
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
