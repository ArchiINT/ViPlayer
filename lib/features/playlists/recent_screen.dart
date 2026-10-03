import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/collections_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/actions/playback.dart';
import '../../shared/widgets/collection_header.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/track_tile.dart';

/// Recently played tracks (each once), newest first.
class RecentScreen extends ConsumerWidget {
  const RecentScreen({super.key});

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.clearHistoryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.clearHistory),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(collectionsRepositoryProvider).clearHistory();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracks = ref.watch(recentlyPlayedProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (tracks.isNotEmpty)
            IconButton(
              tooltip: l10n.clearHistory,
              onPressed: () => _clear(context, ref),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
              artwork: const IconArtwork(icon: Icons.history_rounded),
              title: l10n.recentlyPlayed,
              tracks: tracks,
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.history_rounded,
                title: l10n.recentEmptyTitle,
                message: l10n.recentEmptyBody,
              ),
            )
          else
            SliverFixedExtentList(
              itemExtent: TrackTile.extent,
              delegate: SliverChildBuilderDelegate(
                (context, i) => TrackTile(
                  track: tracks[i],
                  onTap: () => playTrack(context, tracks[i], queue: tracks),
                ),
                childCount: tracks.length,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}
