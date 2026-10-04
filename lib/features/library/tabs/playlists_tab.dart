import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/library/collections_providers.dart';
import '../../../core/library/collections_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/actions/collection_actions.dart';
import '../../../shared/widgets/collection_header.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/glass_panel.dart';

/// Library tab: new playlist, recently played, the user's playlists.
class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final playlists = ref.watch(playlistsProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        GlassGroup(
          children: [
            ListTile(
              leading: const IconArtwork(icon: Icons.add_rounded, size: 48),
              title: Text(l10n.newPlaylist),
              onTap: () async {
                final created = await createPlaylistInteractive(context);
                if (created != null && context.mounted) {
                  context.go(AppRoutes.playlist(created.id));
                }
              },
            ),
            ListTile(
              leading: const IconArtwork(icon: Icons.history_rounded, size: 48),
              title: Text(l10n.recentlyPlayed),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.go(AppRoutes.recent),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.playlistsEmptyBody,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          )
        else
          GlassGroup(
            children: [for (final p in playlists) _PlaylistTile(playlist: p)],
          ),
      ],
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: CoverArt(path: playlist.coverPath, size: 48),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.trackCount(playlist.trackCount)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playlist.isOffline)
            Tooltip(
              message: l10n.availableOffline,
              child: const Icon(
                Icons.offline_pin_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: () => context.go(AppRoutes.playlist(playlist.id)),
    );
  }
}
