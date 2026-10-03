import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_models.dart';
import '../../core/player/player_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../utils/format.dart';

/// Header of a track collection page (playlist, Liked, Recently played):
/// artwork, title, "N tracks · duration", Play / Shuffle and extra actions.
/// Side by side on wide screens, stacked on phones.
class CollectionHeader extends ConsumerWidget {
  const CollectionHeader({
    super.key,
    required this.artwork,
    required this.title,
    required this.tracks,
    this.actions = const [],
  });

  final Widget artwork;
  final String title;
  final List<LibraryTrack> tracks;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.read(playerServiceProvider);
    final totalMs = tracks.fold(0, (sum, t) => sum + t.durationMs);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final info = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          '${l10n.trackCount(tracks.length)} · '
          '${formatTotalDuration(l10n, totalMs)}',
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: tracks.isEmpty ? null : () => player.playQueue(tracks),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.play),
            ),
            OutlinedButton.icon(
              onPressed: tracks.isEmpty
                  ? null
                  : () => player.shufflePlay(tracks),
              icon: const Icon(Icons.shuffle_rounded),
              label: Text(l10n.shuffle),
            ),
            ...actions,
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: wide
          ? Row(
              children: [
                artwork,
                const SizedBox(width: 24),
                Expanded(child: info),
              ],
            )
          : Column(children: [artwork, const SizedBox(height: 20), info]),
    );
  }
}

/// Square artwork made of an icon on an accent gradient — for collections
/// without their own cover (Liked, Recently played).
class IconArtwork extends StatelessWidget {
  const IconArtwork({super.key, required this.icon, this.size = 180});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.large),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.25)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 32,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.42, color: AppColors.base),
    );
  }
}
