import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/file_deleter.dart';
import '../../core/library/library_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/player/player_providers.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import '../utils/sync_texts.dart';
import 'collection_actions.dart';

/// Plays [track]; with [queue], the queue becomes that list (album, search
/// results, …) starting at [track]. Every track list calls this.
void playTrack(
  BuildContext context,
  LibraryTrack track, {
  List<LibraryTrack>? queue,
}) {
  final list = queue ?? [track];
  final start = list.indexOf(track);
  ProviderScope.containerOf(context, listen: false)
      .read(playerServiceProvider)
      .playQueue(list, startIndex: start < 0 ? 0 : start);
}

enum _TrackAction {
  saveToDevice,
  playNext,
  addToQueue,
  like,
  addToPlaylist,
  removeFromPlaylist,
  delete,
}

/// Context menu for a track (long press / right click): queue, likes,
/// playlists, navigation. [position] is where the menu opens (global
/// coordinates). [onRemoveFromPlaylist] adds "Remove from playlist" (when
/// the track is shown inside a playlist).
Future<void> showTrackMenu(
  BuildContext context,
  LibraryTrack track,
  Offset position, {
  VoidCallback? onRemoveFromPlaylist,
}) async {
  final l10n = AppLocalizations.of(context);
  final player = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(playerServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;

  final action = await showMenu<_TrackAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      if (track.isRemote)
        PopupMenuItem(
          value: _TrackAction.saveToDevice,
          child: ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: Text(l10n.saveToDevice),
          ),
        ),
      PopupMenuItem(
        value: _TrackAction.playNext,
        child: ListTile(
          leading: const Icon(Icons.queue_play_next_rounded),
          title: Text(l10n.playNext),
        ),
      ),
      PopupMenuItem(
        value: _TrackAction.addToQueue,
        child: ListTile(
          leading: const Icon(Icons.playlist_add_rounded),
          title: Text(l10n.addToQueue),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: _TrackAction.like,
        child: ListTile(
          leading: Icon(
            track.liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
          title: Text(track.liked ? l10n.unlike : l10n.like),
        ),
      ),
      PopupMenuItem(
        value: _TrackAction.addToPlaylist,
        child: ListTile(
          leading: const Icon(Icons.library_add_rounded),
          title: Text(l10n.addToPlaylist),
        ),
      ),
      if (onRemoveFromPlaylist != null)
        PopupMenuItem(
          value: _TrackAction.removeFromPlaylist,
          child: ListTile(
            leading: const Icon(Icons.playlist_remove_rounded),
            title: Text(l10n.removeFromPlaylist),
          ),
        ),
      if (!track.isRemote) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _TrackAction.delete,
          child: ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
            title: Text(l10n.deleteFromDevice),
          ),
        ),
      ],
    ],
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _TrackAction.saveToDevice:
      try {
        await ProviderScope.containerOf(
          context,
          listen: false,
        ).read(syncServiceProvider).saveToDevice(track.id);
        messenger.showSnackBar(SnackBar(content: Text(l10n.savedToDevice)));
      } on SyncException catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.syncFailure(e.reason))),
        );
      }
    case _TrackAction.playNext:
      await player.playNext(track);
      messenger.showSnackBar(SnackBar(content: Text(l10n.willPlayNext)));
    case _TrackAction.addToQueue:
      await player.addToQueue(track);
      messenger.showSnackBar(SnackBar(content: Text(l10n.addedToQueue)));
    case _TrackAction.like:
      await toggleLike(context, track);
    case _TrackAction.addToPlaylist:
      await showAddToPlaylistSheet(context, [track]);
    case _TrackAction.removeFromPlaylist:
      onRemoveFromPlaylist!();
    case _TrackAction.delete:
      await deleteFromDevice(context, track);
  }
}

/// Asks, then deletes [track]'s file from this device (see
/// LibraryRepository.forgetLocalFiles for what is kept).
Future<void> deleteFromDevice(BuildContext context, LibraryTrack track) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(l10n.deleteFromDeviceConfirm(track.title)),
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
  if (confirmed != true) return;

  final repository = container.read(libraryRepositoryProvider);
  final paths = await repository.filesOf(track.id);
  for (final path in paths) {
    await container.read(playerServiceProvider).removeTrack(path);
  }
  if (!await const FileDeleter().delete(paths)) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.deleteFailed)));
    return;
  }
  await repository.forgetLocalFiles(track.id);
  messenger.showSnackBar(SnackBar(content: Text(l10n.deletedFromDevice)));
}
