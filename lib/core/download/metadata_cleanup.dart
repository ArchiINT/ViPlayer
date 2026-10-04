import '../library/fingerprint.dart';

/// Turns video/upload titles into clean artist + title.
///
/// "Alan Walker - Fade [NCS Release] (Official Video)" by "NCS"
///   -> artist "Alan Walker", title "Fade".
/// Uploads by auto-generated "Artist - Topic" channels already have a clean
/// title; the channel name gives the artist.
abstract final class MetadataCleanup {
  /// Bracketed parts that describe the upload, not the song. Matched
  /// case-insensitively against the text inside () or [].
  static final _noise = RegExp(
    r'^(official\s*(music\s*)?(video|audio|lyric(s)?\s*video|visuali[sz]er)?|'
    r'(official\s*)?lyrics?(\s*video)?|audio|video|music\s*video|mv|hd|hq|'
    r'4k|8k|full\s*hd|1080p|720p|visuali[sz]er|explicit|clean|'
    r'.*\bncs\b.*|.*copyright.*|free\s*download|out\s*now|premiere|'
    // site watermarks: [mp3uk.net], (muzofond.fm)
    r'(www\.)?[\w-]+\.(com|net|org|ru|ua|by|kz|io|me|fm|cc|to|info|biz|club|pro))$',
    caseSensitive: false,
  );

  static final _brackets = RegExp(r'\s*[\(\[]([^\)\]]*)[\)\]]');
  static final _separator = RegExp(r'\s+[-–—|]\s+');

  static ({String artist, String title}) fromUpload({
    required String title,
    required String uploader,
  }) {
    final topic = RegExp(r'^(.*)\s+-\s+Topic$').firstMatch(uploader);
    final cleanTitle = stripNoise(title);
    if (topic != null) {
      return (artist: topic.group(1)!.trim(), title: cleanTitle);
    }

    final parts = cleanTitle.split(_separator);
    if (parts.length >= 2 && parts.first.isNotEmpty) {
      return (
        artist: parts.first.trim(),
        title: parts.sublist(1).join(' - ').trim(),
      );
    }
    return (artist: _cleanUploader(uploader), title: cleanTitle);
  }

  /// Removes bracketed noise ("(Official Video)", "[NCS Release]") but keeps
  /// meaningful parts ("(Remix)", "(feat. X)", "(Live at …)").
  static String stripNoise(String title) {
    final cleaned = title.replaceAllMapped(_brackets, (m) {
      final inner = m.group(1)!.trim();
      return _noise.hasMatch(inner) ? '' : m.group(0)!;
    });
    return cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String _cleanUploader(String uploader) => uploader
      .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
      .replaceAll(RegExp(r'\s*\(?official\)?$', caseSensitive: false), '')
      .trim();

  /// Lower-case word set of [text] (letters/digits, any script).
  static Set<String> words(String text) =>
      Fingerprint.normalize(text).split(' ').where((w) => w.isNotEmpty).toSet();
}
