import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/empty_state.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final neon = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navPlaylists)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              child: ListTile(
                shape: AppTheme.chamfer,
                leading: Icon(Icons.favorite, color: neon),
                title: Text(l10n.playlistsLiked),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
            ),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.queue_music,
              title: l10n.playlistsEmptyTitle,
              message: l10n.playlistsEmptyBody,
            ),
          ),
        ],
      ),
    );
  }
}
