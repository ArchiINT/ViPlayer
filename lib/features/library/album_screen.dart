import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/actions/playback.dart';
import '../../shared/utils/format.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/track_tile.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.albumKey});

  final String albumKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(
      libraryIndexProvider.select((i) => i.value?.albumByKey(albumKey)),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // The page tints itself with its own artwork.
        AmbientBackground(coverPath: album?.coverPath),
        Scaffold(
          appBar: AppBar(),
          // The album can vanish while open (folder removed) — show nothing then.
          body: album == null
              ? const SizedBox.shrink()
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _AlbumHeader(album: album)),
                    SliverFixedExtentList(
                      itemExtent: TrackTile.extent,
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final track = album.tracks[i];
                        return TrackTile(
                          track: track,
                          leadingNumber: track.trackNumber ?? i + 1,
                          showAlbum: false,
                          onTap: () =>
                              playTrack(context, track, queue: album.tracks),
                        );
                      }, childCount: album.tracks.length),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta = [
      if (album.year != null) '${album.year}',
      l10n.trackCount(album.tracks.length),
      formatTotalDuration(l10n, album.durationMs),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Center(
            child: CoverArt(
              path: album.coverPath,
              size: 240,
              radius: AppRadius.large,
              elevated: true,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            album.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => openArtist(context, album.artist),
            child: Text(album.artist, style: const TextStyle(fontSize: 16)),
          ),
          Text(
            meta,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () =>
                playTrack(context, album.tracks.first, queue: album.tracks),
            icon: const Icon(Icons.play_arrow),
            label: Text(l10n.play),
          ),
        ],
      ),
    );
  }
}
