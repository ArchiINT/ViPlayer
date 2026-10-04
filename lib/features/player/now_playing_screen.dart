import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/library_models.dart';
import '../../core/player/player_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/ambient_background.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/glass_panel.dart';
import '../../shared/widgets/like_button.dart';
import '../../shared/widgets/player_controls.dart';
import 'up_next.dart';

/// Full-screen player: large cover over its own blurred artwork, title,
/// seek bar and controls. Wide windows show the queue alongside.
/// Swipe down or press back to close.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final track = ref.watch(currentTrackProvider);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;

    // Nothing to show (queue cleared) — leave.
    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && context.canPop()) context.pop();
      });
      return const SizedBox.shrink();
    }

    final player = _PlayerColumn(track: track, wide: wide);

    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) context.pop();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          AmbientBackground(coverPath: track.coverPath),
          Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: l10n.close,
                onPressed: context.pop,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
              ),
              title: Text(
                l10n.nowPlaying,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              centerTitle: true,
              actions: [
                LikeButton(track: track, size: 26),
                const SizedBox(width: 4),
              ],
            ),
            body: SafeArea(
              top: false,
              child: wide
                  ? Row(
                      children: [
                        Expanded(flex: 5, child: player),
                        const Expanded(
                          flex: 4,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(0, 8, 24, 24),
                            child: GlassPanel(child: UpNextPanel()),
                          ),
                        ),
                      ],
                    )
                  : _WithUpNextSheet(child: player),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  const _PlayerColumn({required this.track, required this.wide});

  final LibraryTrack track;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cover takes what is left after title + controls (~260 px).
        final coverSize = (constraints.maxHeight - 290)
            .clamp(160.0, 520.0)
            .clamp(0.0, constraints.maxWidth - 48);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'now-playing-cover',
                child: AnimatedSwitcher(
                  duration: AppMotion.slow,
                  child: CoverArt(
                    key: ValueKey(track.coverPath),
                    path: track.coverPath,
                    size: coverSize,
                    radius: AppRadius.large,
                    elevated: true,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              AnimatedSwitcher(
                duration: AppMotion.normal,
                child: Column(
                  key: ValueKey(track.id),
                  children: [
                    Text(
                      track.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    if (track.artist.isNotEmpty)
                      Text(
                        track.artist,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: const SeekBar(),
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShuffleButton(),
                  SizedBox(width: 12),
                  SkipButton.previous(size: 40),
                  SizedBox(width: 12),
                  PlayPauseButton(size: 72, filled: true),
                  SizedBox(width: 12),
                  SkipButton.next(size: 40),
                  SizedBox(width: 12),
                  RepeatButton(),
                ],
              ),
              if (wide) ...[const SizedBox(height: 12), const VolumeSlider()],
            ],
          ),
        );
      },
    );
  }
}

/// Phone layout: the player, with "Up next" as a sheet docked at the bottom
/// (a strip when collapsed; drag it up to see and edit the queue).
class _WithUpNextSheet extends StatelessWidget {
  const _WithUpNextSheet({required this.child});

  final Widget child;

  static const _collapsedHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final collapsed = (_collapsedHeight / constraints.maxHeight).clamp(
          0.05,
          0.3,
        );
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: _collapsedHeight),
              child: child,
            ),
            DraggableScrollableSheet(
              initialChildSize: collapsed,
              minChildSize: collapsed,
              maxChildSize: 0.9,
              snap: true,
              // Material (not a decorated box) so row ripples show.
              builder: (context, controller) => Material(
                color: AppColors.overlay,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.large),
                  ),
                  side: BorderSide(color: AppColors.glassBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Grab handle.
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(child: UpNextPanel(scrollController: controller)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
