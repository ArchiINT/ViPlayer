import 'package:flutter/material.dart';

import '../../core/library/library_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../utils/format.dart';
import 'cover_art.dart';

/// One row in any track list: a faint glass pill, separated from its
/// neighbours by a small gap.
///
/// Fixed height ([extent], gap included) so lists can use `itemExtent`,
/// which keeps scrolling through huge libraries cheap.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.leadingNumber,
    this.showAlbum = true,
  });

  static const extent = 68.0;
  static const _gap = 4.0;

  final LibraryTrack track;
  final VoidCallback? onTap;

  /// Shows the track number instead of the cover (album screens).
  final int? leadingNumber;
  final bool showAlbum;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final artist = track.artist.isEmpty ? l10n.unknownArtist : track.artist;
    final subtitle = showAlbum && track.album.isNotEmpty
        ? '$artist · ${track.album}'
        : artist;
    const radius = BorderRadius.all(Radius.circular(AppRadius.medium));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, _gap / 2, 12, _gap / 2),
      child: Material(
        color: AppColors.glass,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (leadingNumber != null)
                  SizedBox(
                    width: 44,
                    child: Text(
                      '$leadingNumber',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 14,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                else
                  CoverArt(path: track.coverPath, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (track.liked) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.favorite_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ],
                const SizedBox(width: 12),
                Text(
                  formatTrackDuration(track.durationMs),
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
