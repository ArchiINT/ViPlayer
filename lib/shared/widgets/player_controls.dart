import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/audio_backend.dart';
import '../../core/player/player_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../utils/format.dart';

/// Play/pause button whose icon morphs between the two states.
class PlayPauseButton extends ConsumerStatefulWidget {
  const PlayPauseButton({super.key, this.size = 40, this.filled = false});

  final double size;

  /// Big round accent-coloured button (full player) vs. plain icon.
  final bool filled;

  @override
  ConsumerState<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends ConsumerState<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final _morph = AnimationController(
    vsync: this,
    duration: AppMotion.normal,
    value: ref.read(playerSnapshotProvider).playing ? 1 : 0,
  );

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final playing = ref.watch(playerSnapshotProvider.select((s) => s.playing));
    ref.listen(
      playerSnapshotProvider.select((s) => s.playing),
      (_, isPlaying) => isPlaying ? _morph.forward() : _morph.reverse(),
    );
    final accent = Theme.of(context).colorScheme.primary;

    final icon = AnimatedIcon(
      icon: AnimatedIcons.play_pause,
      progress: CurvedAnimation(parent: _morph, curve: AppMotion.curve),
      size: widget.size * (widget.filled ? 0.5 : 1),
      color: widget.filled ? AppColors.base : AppColors.textPrimary,
    );
    final onPressed = ref.read(playerServiceProvider).playOrPause;
    final tooltip = playing ? l10n.pause : l10n.play;

    if (!widget.filled) {
      return IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon);
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: widget.size,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class ShuffleButton extends ConsumerWidget {
  const ShuffleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(playerSnapshotProvider.select((s) => s.shuffle));
    return IconButton(
      tooltip: AppLocalizations.of(context).shuffle,
      isSelected: on,
      onPressed: ref.read(playerServiceProvider).toggleShuffle,
      color: AppColors.textSecondary,
      selectedIcon: Icon(
        Icons.shuffle_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      icon: const Icon(Icons.shuffle_rounded),
    );
  }
}

class RepeatButton extends ConsumerWidget {
  const RepeatButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(playerSnapshotProvider.select((s) => s.repeat));
    final accent = Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: switch (mode) {
        PlaybackRepeat.off => l10n.repeatOff,
        PlaybackRepeat.all => l10n.repeatAll,
        PlaybackRepeat.one => l10n.repeatOne,
      },
      onPressed: ref.read(playerServiceProvider).cycleRepeat,
      icon: Icon(
        mode == PlaybackRepeat.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        color: mode == PlaybackRepeat.off ? AppColors.textSecondary : accent,
      ),
    );
  }
}

class SkipButton extends ConsumerWidget {
  const SkipButton.previous({super.key, this.size = 32}) : forward = false;
  const SkipButton.next({super.key, this.size = 32}) : forward = true;

  final bool forward;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.read(playerServiceProvider);
    return IconButton(
      tooltip: forward ? l10n.next : l10n.previous,
      iconSize: size,
      onPressed: forward ? player.next : player.previous,
      icon: Icon(
        forward ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
      ),
    );
  }
}

/// Seek slider with elapsed / total time. Only this widget rebuilds with the
/// position; while dragging it shows the drag position and seeks on release.
class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key});

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(
      playerSnapshotProvider.select((s) => s.duration),
    );
    final maxMs = duration.inMilliseconds.toDouble();
    final valueMs = (_dragMs ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs <= 0 ? 0.0 : maxMs,
    );
    const timeStyle = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.textSecondary,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            max: maxMs <= 0 ? 1 : maxMs,
            value: maxMs <= 0 ? 0 : valueMs,
            onChanged: maxMs <= 0 ? null : (v) => setState(() => _dragMs = v),
            onChangeEnd: (v) {
              ref
                  .read(playerServiceProvider)
                  .seek(Duration(milliseconds: v.round()));
              setState(() => _dragMs = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatTrackDuration(valueMs.round()), style: timeStyle),
              Text(formatTrackDuration(maxMs.round()), style: timeStyle),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thin progress line (mini player). Cheap: no gestures, no labels.
class PlaybackProgressLine extends ConsumerWidget {
  const PlaybackProgressLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(
      playerSnapshotProvider.select((s) => s.duration),
    );
    final fraction = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return LinearProgressIndicator(
      value: fraction,
      minHeight: 2,
      backgroundColor: Colors.transparent,
    );
  }
}

/// Volume slider (desktop).
class VolumeSlider extends ConsumerWidget {
  const VolumeSlider({super.key, this.width = 140});

  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(playerSnapshotProvider.select((s) => s.volume));
    final player = ref.read(playerServiceProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: AppLocalizations.of(context).volume,
          onPressed: () => player.setVolume(volume > 0 ? 0 : 70),
          icon: Icon(
            volume == 0
                ? Icons.volume_off_rounded
                : volume < 50
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(
          width: width,
          child: Slider(max: 100, value: volume, onChanged: player.setVolume),
        ),
      ],
    );
  }
}
