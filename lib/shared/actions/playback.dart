import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_models.dart';
import '../../core/player/player_providers.dart';
import '../../core/router/app_router.dart';
import '../../l10n/generated/app_localizations.dart';

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

enum _TrackAction { playNext, addToQueue, album, artist }

/// Context menu for a track (long press / right click): queue actions and
/// navigation. [position] is where the menu opens (global coordinates).
Future<void> showTrackMenu(
  BuildContext context,
  LibraryTrack track,
  Offset position,
) async {
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
      if (track.album.isNotEmpty)
        PopupMenuItem(
          value: _TrackAction.album,
          child: ListTile(
            leading: const Icon(Icons.album_outlined),
            title: Text(l10n.goToAlbum),
          ),
        ),
      if (track.artist.isNotEmpty)
        PopupMenuItem(
          value: _TrackAction.artist,
          child: ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(l10n.goToArtist),
          ),
        ),
    ],
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _TrackAction.playNext:
      await player.playNext(track);
      messenger.showSnackBar(SnackBar(content: Text(l10n.willPlayNext)));
    case _TrackAction.addToQueue:
      await player.addToQueue(track);
      messenger.showSnackBar(SnackBar(content: Text(l10n.addedToQueue)));
    case _TrackAction.album:
      openAlbum(context, track.albumKey);
    case _TrackAction.artist:
      openArtist(context, track.artist);
  }
}
