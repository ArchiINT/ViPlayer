import 'package:flutter/material.dart';

import '../../core/library/library_models.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import 'cover_art.dart';

class ArtistTile extends StatelessWidget {
  const ArtistTile({super.key, required this.artist, required this.onTap});

  static const extent = 68.0;

  final Artist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final albums = artist.albums.length;
    final meta = [
      l10n.trackCount(artist.tracks.length),
      if (albums > 0) l10n.albumCount(albums),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: extent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              CoverArt(path: artist.coverPath, size: 48, radius: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
