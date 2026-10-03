/// Content identity of a song, used to recognise the same track on different
/// devices (where file paths differ) and to merge duplicate files into one
/// track. See docs/SYNC.md.
///
/// Format: `m:<artist>|<title>|<duration bucket>` with normalized text.
/// Changing the format changes every track's identity — treat it as a
/// database migration.
abstract final class Fingerprint {
  /// Durations within the same bucket count as equal: the same song from two
  /// sources often differs by a second or so.
  static const bucketMs = 3000;

  static String fromMetadata({
    required String artist,
    required String title,
    required int durationMs,
  }) {
    final bucket = (durationMs / bucketMs).round();
    return 'm:${normalize(artist)}|${normalize(title)}|$bucket';
  }

  /// Lowercase, letters/digits only, single spaces. Works for any script
  /// (Latin, Cyrillic, …), so "Чёрный Лёд!" and "чёрный лёд" match.
  static String normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}
