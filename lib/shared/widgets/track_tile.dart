import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_models.dart';
import '../../core/player/player_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../actions/playback.dart';
import '../utils/format.dart';
import 'cover_art.dart';

/// One row in any track list: a faint glass pill, separated from its
/// neighbours by a small gap. The playing track is highlighted; long press
/// or right click opens the track menu (play next, add to queue, …).
///
/// Fixed height ([extent], gap included) so lists can use `itemExtent`,
/// which keeps scrolling through huge libraries cheap.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.leadingNumber,
    this.showAlbum = true,
    this.trailing,
    this.onRemoveFromPlaylist,
  });

  static const extent = 68.0;
  static const _gap = 4.0;

  final LibraryTrack track;
  final VoidCallback? onTap;

  /// Shows the track number instead of the cover (album screens).
  final int? leadingNumber;
  final bool showAlbum;

  /// Extra widget at the end of the row (e.g. a drag handle).
  final Widget? trailing;

  /// Set inside a playlist: adds "Remove from playlist" to the menu.
  final VoidCallback? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Each row rebuilds only when *its* playing state flips.
    final isCurrent = ref.watch(
      currentTrackProvider.select((t) => t?.id == track.id),
    );
    final accent = theme.colorScheme.primary;
    final artist = track.artist.isEmpty ? l10n.unknownArtist : track.artist;
    final subtitle = showAlbum && track.album.isNotEmpty
        ? '$artist · ${track.album}'
        : artist;
    const radius = BorderRadius.all(Radius.circular(AppRadius.medium));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, _gap / 2, 12, _gap / 2),
      child: Material(
        color: isCurrent ? AppColors.glassHighlight : AppColors.glass,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => _openMenu(context),
          onSecondaryTapUp: (d) => showTrackMenu(
            context,
            track,
            d.globalPosition,
            onRemoveFromPlaylist: onRemoveFromPlaylist,
          ),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (isCurrent && leadingNumber != null)
                  SizedBox(
                    width: 44,
                    child: Icon(Icons.graphic_eq_rounded, color: accent),
                  )
                else if (leadingNumber != null)
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
                          color: isCurrent ? accent : null,
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
                if (track.isRemote) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: l10n.onYourNetwork,
                    child: const Icon(
                      Icons.wifi_rounded,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
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
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMenu(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    showTrackMenu(
      context,
      track,
      box.localToGlobal(box.size.centerRight(Offset.zero)),
      onRemoveFromPlaylist: onRemoveFromPlaylist,
    );
  }
}
