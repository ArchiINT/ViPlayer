import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/actions/playback.dart';
import '../../shared/widgets/album_card.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/track_tile.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.artistName});

  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final artist = ref.watch(
      libraryIndexProvider.select((i) => i.value?.artistByName(artistName)),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // The page tints itself with its own artwork.
        AmbientBackground(coverPath: artist?.coverPath),
        Scaffold(
          appBar: AppBar(),
          body: artist == null
              ? const SizedBox.shrink()
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _ArtistHeader(artist: artist)),
                    if (artist.albums.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: SectionHeader(l10n.libraryAlbums),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 210,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: artist.albums.length,
                            itemBuilder: (context, i) => SizedBox(
                              width: 160,
                              child: AlbumCard(
                                album: artist.albums[i],
                                onTap: () =>
                                    openAlbum(context, artist.albums[i].key),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: SectionHeader(l10n.libraryTracks),
                    ),
                    SliverFixedExtentList(
                      itemExtent: TrackTile.extent,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => TrackTile(
                          track: artist.tracks[i],
                          onTap: () => playTrack(
                            context,
                            artist.tracks[i],
                            queue: artist.tracks,
                          ),
                        ),
                        childCount: artist.tracks.length,
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final meta = [
      l10n.trackCount(artist.tracks.length),
      if (artist.albums.isNotEmpty) l10n.albumCount(artist.albums.length),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          CoverArt(
            path: artist.coverPath,
            size: 112,
            radius: 56,
            elevated: true,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  meta,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => playTrack(
                    context,
                    artist.tracks.first,
                    queue: artist.tracks,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.play),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
