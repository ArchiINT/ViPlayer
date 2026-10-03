import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/player/player_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/glass_panel.dart';
import '../../shared/widgets/player_controls.dart';

/// Compact player docked above the navigation (phone) or at the bottom of
/// the content (desktop). Tap or swipe up opens the full player.
/// Slides in when something starts playing.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const height = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return AnimatedSwitcher(
      duration: AppMotion.normal,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: track == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: const ValueKey('mini'),
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: GestureDetector(
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < -200) {
                    context.push(AppRoutes.player);
                  }
                },
                child: GlassPanel(
                  strong: true,
                  radius: AppRadius.large,
                  child: InkWell(
                    onTap: () => context.push(AppRoutes.player),
                    child: SizedBox(
                      height: height,
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, right: 4),
                              child: Row(
                                children: [
                                  Hero(
                                    tag: 'now-playing-cover',
                                    child: CoverArt(
                                      path: track.coverPath,
                                      size: 46,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration: AppMotion.normal,
                                      layoutBuilder: (current, previous) =>
                                          Stack(
                                            alignment: Alignment.centerLeft,
                                            children: [...previous, ?current],
                                          ),
                                      child: _TitleBlock(
                                        key: ValueKey(track.id),
                                        title: track.title,
                                        artist: track.artist,
                                      ),
                                    ),
                                  ),
                                  if (wide) const SkipButton.previous(size: 26),
                                  const PlayPauseButton(size: 30),
                                  const SkipButton.next(size: 26),
                                  if (wide) ...[
                                    const SizedBox(width: 8),
                                    const VolumeSlider(width: 110),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const PlaybackProgressLine(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({super.key, required this.title, required this.artist});

  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (artist.isNotEmpty)
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}
