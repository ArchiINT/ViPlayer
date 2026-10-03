import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/collections_providers.dart';
import '../../core/library/collections_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/actions/collection_actions.dart';
import '../../shared/actions/playback.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/collection_header.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/track_tile.dart';

enum _PlaylistAction { rename, offline, delete }

/// One playlist: header with actions, tracks in order. Drag the handle to
/// reorder; the track menu removes a track from the playlist.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    PlaylistSummary playlist,
    _PlaylistAction action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(collectionsRepositoryProvider);
    switch (action) {
      case _PlaylistAction.rename:
        final name = await showPlaylistNameDialog(
          context,
          initial: playlist.name,
          title: l10n.rename,
          action: l10n.save,
        );
        if (name != null) await repo.renamePlaylist(playlist.id, name);
      case _PlaylistAction.offline:
        await repo.setPlaylistOffline(
          playlist.id,
          offline: !playlist.isOffline,
        );
      case _PlaylistAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.deletePlaylist),
            content: Text(l10n.deletePlaylistConfirm(playlist.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        context.pop();
        await repo.deletePlaylist(playlist.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final playlist = ref.watch(playlistProvider(playlistId));
    final items =
        ref.watch(playlistItemsProvider(playlistId)).value ?? const [];
    final tracks = [for (final i in items) i.track];
    final repo = ref.read(collectionsRepositoryProvider);
    final cover = items.map((i) => i.track.coverPath).nonNulls.firstOrNull;

    return Stack(
      fit: StackFit.expand,
      children: [
        AmbientBackground(coverPath: cover),
        Scaffold(
          appBar: AppBar(),
          body: playlist == null
              ? const SizedBox.shrink()
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: CollectionHeader(
                        artwork: CoverArt(
                          path: cover,
                          size: 180,
                          radius: AppRadius.large,
                          elevated: true,
                        ),
                        title: playlist.name,
                        tracks: tracks,
                        actions: [
                          PopupMenuButton<_PlaylistAction>(
                            icon: const Icon(Icons.more_horiz_rounded),
                            onSelected: (a) =>
                                _onAction(context, ref, playlist, a),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: _PlaylistAction.rename,
                                child: ListTile(
                                  leading: const Icon(Icons.edit_rounded),
                                  title: Text(l10n.rename),
                                ),
                              ),
                              CheckedPopupMenuItem(
                                value: _PlaylistAction.offline,
                                checked: playlist.isOffline,
                                child: Text(l10n.availableOffline),
                              ),
                              PopupMenuItem(
                                value: _PlaylistAction.delete,
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColors.error,
                                  ),
                                  title: Text(l10n.deletePlaylist),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (items.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.playlist_add_rounded,
                          title: l10n.playlistEmptyTitle,
                          message: l10n.playlistEmptyBody,
                        ),
                      )
                    else
                      SliverReorderableList(
                        itemCount: items.length,
                        itemExtent: TrackTile.extent,
                        onReorderItem: (from, to) {
                          // [to] is the final index; find its neighbours.
                          final rest = [...items]..removeAt(from);
                          repo.moveEntry(
                            playlistId,
                            items[from].entryId,
                            afterEntryId: to > 0 ? rest[to - 1].entryId : null,
                            beforeEntryId: to < rest.length
                                ? rest[to].entryId
                                : null,
                          );
                        },
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return TrackTile(
                            key: ValueKey(item.entryId),
                            track: item.track,
                            onTap: () =>
                                playTrack(context, item.track, queue: tracks),
                            onRemoveFromPlaylist: () =>
                                repo.removeFromPlaylist(item.entryId),
                            trailing: ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                  ],
                ),
        ),
      ],
    );
  }
}
