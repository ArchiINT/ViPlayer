import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/empty_state.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navLibrary)),
      body: EmptyState(
        icon: Icons.library_music_outlined,
        title: l10n.libraryEmptyTitle,
        message: l10n.libraryEmptyBody,
        action: OutlinedButton.icon(
          onPressed: () => context.go(AppRoutes.settings),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: Text(l10n.settingsMusicFolders),
        ),
      ),
    );
  }
}
