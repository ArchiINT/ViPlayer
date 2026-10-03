import '../../l10n/generated/app_localizations.dart';

/// `3:07`, `1:02:45` — for a single track.
String formatTrackDuration(int ms) {
  final total = Duration(milliseconds: ms);
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}

/// `1 h 23 min` / `42 min` — for albums and whole libraries.
String formatTotalDuration(AppLocalizations l10n, int ms) {
  final total = Duration(milliseconds: ms);
  final minutes = total.inMinutes.remainder(60);
  return total.inHours > 0
      ? l10n.durationHoursMinutes(total.inHours, minutes)
      : l10n.durationMinutes(total.inMinutes);
}
