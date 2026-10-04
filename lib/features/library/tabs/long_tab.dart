import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/library/library_models.dart';
import '../../../core/library/library_providers.dart';
import '../../../core/player/player_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/actions/playback.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/empty_state.dart';

/// Library tab for long recordings (audiobooks, podcasts): each shows how
/// far it was listened to and continues from there.
class LongTab extends ConsumerWidget {
  const LongTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracks = ref.watch(longTracksProvider);
    // Positions change while listening; refresh with the player.
    ref.watch(currentTrackProvider);
    final player = ref.read(playerServiceProvider);

    if (tracks.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book_rounded,
        title: l10n.longEmptyTitle,
        message: l10n.longEmptyBody(
          ref.watch(settingsProvider.select((s) => s.longAudioMinutes)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemExtent: 84,
      itemCount: tracks.length,
      itemBuilder: (context, i) => _LongTile(
        track: tracks[i],
        resumeAt: player.resumePositionOf(tracks[i].id),
      ),
    );
  }
}

class _LongTile extends StatelessWidget {
  const _LongTile({required this.track, this.resumeAt});

  final LibraryTrack track;
  final Duration? resumeAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final total = track.durationMs;
    final progress = resumeAt == null || total == 0
        ? 0.0
        : (resumeAt!.inMilliseconds / total).clamp(0.0, 1.0);
    const radius = BorderRadius.all(Radius.circular(AppRadius.medium));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: AppColors.glass,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          // A book plays on its own; it does not run into the next one.
          onTap: () => playTrack(context, track),
          onLongPress: () {
            final box = context.findRenderObject()! as RenderBox;
            showTrackMenu(
              context,
              track,
              box.localToGlobal(box.size.centerRight(Offset.zero)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CoverArt(path: track.coverPath, size: 60),
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
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        resumeAt == null
                            ? '${track.artist.isEmpty ? l10n.unknownArtist : track.artist} · ${formatTrackDuration(total)}'
                            : l10n.resumeAt(
                                formatTrackDuration(resumeAt!.inMilliseconds),
                                formatTrackDuration(total),
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: progress, minHeight: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
