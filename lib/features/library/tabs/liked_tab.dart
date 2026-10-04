import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/library/collections_providers.dart';
import '../../../core/player/player_providers.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/actions/playback.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/track_tile.dart';

/// Library tab: liked tracks, most recently liked first.
class LikedTab extends ConsumerWidget {
  const LikedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracks = ref.watch(likedTracksProvider);
    if (tracks.isEmpty) {
      return EmptyState(
        icon: Icons.favorite_border_rounded,
        title: l10n.likedEmptyTitle,
        message: l10n.likedEmptyBody,
      );
    }
    final player = ref.read(playerServiceProvider);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => player.playQueue(tracks),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l10n.play),
                ),
                OutlinedButton.icon(
                  onPressed: () => player.shufflePlay(tracks),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: Text(l10n.shuffle),
                ),
              ],
            ),
          ),
        ),
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
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}
