import 'download_models.dart';
import 'metadata_cleanup.dart';

/// Picks the YouTube upload that is the same recording as a Spotify track
/// (Spotify audio itself cannot be downloaded — see docs/DOWNLOADS.md).
///
/// Scores each search result on duration, title and artist, and penalises
/// versions the user did not ask for (live, cover, sped up, …) unless the
/// wanted title says so too.
abstract final class TrackMatcher {
  /// Results scoring below this are not the song.
  static const minScore = 50.0;

  static const _variants = {
    'live',
    'cover',
    'remix',
    'karaoke',
    'instrumental',
    'acoustic',
    'sped',
    'slowed',
    'reverb',
    'nightcore',
    '8d',
    'edit',
    'extended',
    'tutorial',
    'reaction',
  };

  static DownloadCandidate? best(
    DownloadCandidate wanted,
    List<DownloadCandidate> results,
  ) {
    DownloadCandidate? best;
    var bestScore = minScore;
    for (final r in results) {
      final s = score(wanted, r);
      if (s > bestScore) {
        best = r;
        bestScore = s;
      }
    }
    return best;
  }

  static double score(DownloadCandidate wanted, DownloadCandidate result) {
    var score = 0.0;

    // Duration: the strongest signal. Same recording ⇒ within a few seconds.
    final diff = (wanted.durationMs - result.durationMs).abs() / 1000;
    if (wanted.durationMs > 0 && result.durationMs > 0) {
      score += switch (diff) {
        <= 2 => 40,
        <= 5 => 30,
        <= 10 => 15,
        <= 20 => 0,
        _ => -40,
      };
    }

    // Title words present in the result.
    final wantedTitle = MetadataCleanup.words(wanted.title);
    final resultText = MetadataCleanup.words(
      '${result.title} ${result.artist}',
    );
    if (wantedTitle.isNotEmpty) {
      final found = wantedTitle.where(resultText.contains).length;
      score += 35 * found / wantedTitle.length;
    }

    // Artist (first credited one is enough).
    final wantedArtist = MetadataCleanup.words(
      wanted.artist.split(RegExp(r',|&|\bfeat\b|\bft\b')).first,
    );
    if (wantedArtist.isNotEmpty) {
      final found = wantedArtist.where(resultText.contains).length;
      score += 25 * found / wantedArtist.length;
    }

    // Unwanted versions.
    final wantedAll = MetadataCleanup.words('${wanted.title} ${wanted.album}');
    for (final v in _variants) {
      if (resultText.contains(v) && !wantedAll.contains(v)) score -= 30;
    }
    return score;
  }
}
