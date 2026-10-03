import 'package:flutter/material.dart';

import '../../core/library/library_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../actions/collection_actions.dart';

/// Heart toggle for a track; gives a short "pop" when liked.
class LikeButton extends StatefulWidget {
  const LikeButton({super.key, required this.track, this.size = 24});

  final LibraryTrack track;
  final double size;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(
    vsync: this,
    duration: AppMotion.normal,
  );

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LikeButton old) {
    super.didUpdateWidget(old);
    final becameLiked =
        widget.track.id == old.track.id &&
        widget.track.liked &&
        !old.track.liked;
    if (becameLiked) _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final liked = widget.track.liked;
    final accent = Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: liked ? l10n.unlike : l10n.like,
      onPressed: () => toggleLike(context, widget.track),
      icon: ScaleTransition(
        // 1 -> 1.3 -> 1
        scale: TweenSequence([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 1),
        ]).animate(CurvedAnimation(parent: _pop, curve: AppMotion.curve)),
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: widget.size,
          color: liked ? accent : AppColors.textSecondary,
        ),
      ),
    );
  }
}
