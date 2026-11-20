import 'package:flutter/material.dart';

import '../../core/library/library_models.dart';
import '../../core/platform/app_log.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../actions/collection_actions.dart';

/// Heart toggle for a track; gives a short "pop" when liked.
///
/// The heart flips the moment it is tapped: the saved state reaches the
/// widget only after the library has been re-read (a noticeable lag on a
/// phone). Until then the tapped state is shown; a failed save reverts it.
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

  /// The state just tapped, shown until the library confirms it.
  bool? _pending;

  @override
  void didUpdateWidget(LikeButton old) {
    super.didUpdateWidget(old);
    if (widget.track.id != old.track.id || widget.track.liked == _pending) {
      _pending = null;
    }
  }

  Future<void> _toggle() async {
    final track = widget.track;
    final liked = !(_pending ?? track.liked);
    // Tracks streamed from the PC have no row here: nothing would confirm.
    if (!track.isRemote) setState(() => _pending = liked);
    if (liked) _pop.forward(from: 0);
    try {
      await setLike(context, track, liked: liked);
    } on Object catch (e, stack) {
      AppLog.error('like', e, stack);
      if (mounted && widget.track.id == track.id) {
        setState(() => _pending = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final liked = _pending ?? widget.track.liked;
    final accent = Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: liked ? l10n.unlike : l10n.like,
      onPressed: _toggle,
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
