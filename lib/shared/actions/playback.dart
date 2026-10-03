import 'package:flutter/material.dart';

import '../../core/library/library_models.dart';
import '../../l10n/generated/app_localizations.dart';

/// What tapping a track does. Placeholder until the player (stage 3) lands;
/// every track list calls this so the switch happens in one place.
void playTrack(
  BuildContext context,
  LibraryTrack track, {
  List<LibraryTrack>? queue,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).playbackComingSoon)),
    );
}
