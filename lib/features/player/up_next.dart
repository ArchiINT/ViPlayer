import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/player/player_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/cover_art.dart';

/// The tracks after the current one: drag to reorder, swipe to remove,
/// "Add" to put more from the library in.
///
/// [scrollController] lets the list drive a draggable sheet (phone layout).
class UpNextPanel extends ConsumerWidget {
  const UpNextPanel({super.key, this.scrollController});

  final ScrollController? scrollController;

  static const _rowHeight = 60.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(playerSnapshotProvider);
    final player = ref.read(playerServiceProvider);
    final offset = snapshot.index + 1;
    final upcoming = offset <= 0 || offset >= snapshot.queue.length
        ? const <LibraryTrack>[]
        : snapshot.queue.sublist(offset);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: l10n.upNext,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '  ${upcoming.length}',
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            onPressed: () => showAddToQueueSheet(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.addTracks),
          ),
        ],
      ),
    );

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(child: header),
        if (upcoming.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                l10n.queueEmpty,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          SliverReorderableList(
            itemCount: upcoming.length,
            itemExtent: _rowHeight,
            // Positions are relative to the upcoming part of the queue.
            onReorderItem: (from, to) =>
                player.reorder(offset + from, offset + to),
            itemBuilder: (context, i) {
              final track = upcoming[i];
              return Dismissible(
                // The same song may be queued twice: key by position too.
                key: ValueKey('${track.id}#${offset + i}'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => player.removeAt(offset + i),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: AppColors.error.withValues(alpha: 0.2),
                  child: const Icon(Icons.delete_outline_rounded),
                ),
                child: ListTile(
                  onTap: () => player.jumpTo(offset + i),
                  leading: CoverArt(path: track.coverPath, size: 40),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
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
                ),
              );
            },
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

/// Library search to add tracks to the queue. Stays open so several can be
/// added; each row offers "play next" and "add to the end".
Future<void> showAddToQueueSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.overlay,
      showDragHandle: true,
      builder: (context) =>
          const FractionallySizedBox(heightFactor: 0.85, child: _AddToQueue()),
    );

class _AddToQueue extends ConsumerStatefulWidget {
  const _AddToQueue();

  @override
  ConsumerState<_AddToQueue> createState() => _AddToQueueState();
}

class _AddToQueueState extends ConsumerState<_AddToQueue> {
  String _query = '';

  /// Tracks added during this visit, for a check mark.
  final _added = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final index = ref.watch(libraryIndexProvider).value ?? LibraryIndex.empty;
    final player = ref.read(playerServiceProvider);
    final tracks = _query.trim().isEmpty
        ? LibraryIndex.sortTracks(index.tracks, TrackSort.title)
        : index.search(_query);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemExtent: 64,
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final t = tracks[i];
              final done = _added.contains(t.id);
              void add({required bool next}) {
                next ? player.playNext(t) : player.addToQueue(t);
                setState(() => _added.add(t.id));
              }

              return ListTile(
                onTap: () => add(next: false),
                leading: CoverArt(path: t.coverPath, size: 44),
                title: Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.playNext,
                      onPressed: () => add(next: true),
                      icon: const Icon(Icons.queue_play_next_rounded),
                    ),
                    IconButton(
                      tooltip: l10n.addToQueue,
                      onPressed: () => add(next: false),
                      icon: Icon(
                        done ? Icons.check_rounded : Icons.playlist_add_rounded,
                        color: done
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
