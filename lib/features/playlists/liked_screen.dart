import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/collections_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/actions/playback.dart';
import '../../shared/widgets/collection_header.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/track_tile.dart';

/// Liked tracks, most recently liked first.
class LikedScreen extends ConsumerWidget {
  const LikedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracks = ref.watch(likedTracksProvider);

    return Scaffold(
      appBar: AppBar(),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
              artwork: const IconArtwork(icon: Icons.favorite_rounded),
              title: l10n.playlistsLiked,
              tracks: tracks,
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.favorite_border_rounded,
                title: l10n.likedEmptyTitle,
                message: l10n.likedEmptyBody,
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
