import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../download/metadata_cleanup.dart';
import 'cover_store.dart';
import 'mp4_tags.dart';

// Blocking file-system work for the library scanner. Everything here is
// synchronous and meant to run inside a background isolate (Isolate.run) so
// the UI never stutters, even on libraries with tens of thousands of files.

/// Audio formats the library picks up (video containers are ignored).
const audioExtensions = {
  '.mp3',
  '.m4a',
  '.aac',
  '.flac',
  '.ogg',
  '.oga',
  '.opus',
  '.wav',
  '.aif',
  '.aiff',
  '.aifc',
  '.ape',
};

bool isAudioPath(String path) =>
    audioExtensions.contains(p.extension(path).toLowerCase());

/// A directory to scan. [folderId] links found files to a LibraryFolders row
/// (null for the download folder).
class ScanRoot {
  const ScanRoot(this.path, {this.folderId});

  final String path;
  final int? folderId;
}

/// An audio file seen on disk.
class FoundFile {
  const FoundFile({
    required this.path,
    required this.sizeBytes,
    required this.modifiedMs,
    this.folderId,
  });

  final String path;
  final int sizeBytes;
  final int modifiedMs;
  final int? folderId;
}

class DiscoveryResult {
  const DiscoveryResult(this.files, this.directories);

  final List<FoundFile> files;

  /// Every directory visited — used by the desktop folder watcher.
  final List<String> directories;
}

/// Recursively lists audio files under [roots]. Hidden directories and
/// Android's app-private `Android/` tree are skipped; symlinks are not
/// followed (no loops). A file under several roots is reported once, for the
/// most specific (deepest) root.
DiscoveryResult discoverAudioFiles(List<ScanRoot> roots) {
  final sorted = [...roots]
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  final files = <String, FoundFile>{};
  final directories = <String>[];

  for (final root in sorted) {
    final pending = [root.path];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      directories.add(dir);
      final List<FileSystemEntity> entries;
      try {
        entries = Directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        continue; // unreadable or vanished — skip quietly
      }
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        if (entry is Directory) {
          if (_isSkippedDirectory(entry.path)) continue;
          pending.add(entry.path);
        } else if (entry is File && isAudioPath(entry.path)) {
          if (files.containsKey(entry.path)) continue; // deeper root won
          try {
            final stat = entry.statSync();
            files[entry.path] = FoundFile(
              path: entry.path,
              sizeBytes: stat.size,
              modifiedMs: stat.modified.millisecondsSinceEpoch,
              folderId: root.folderId,
            );
          } on FileSystemException {
            continue;
          }
        }
      }
    }
  }
  return DiscoveryResult(files.values.toList(), directories.toSet().toList());
}

bool _isSkippedDirectory(String path) =>
    path.endsWith('/Android/data') || path.endsWith('/Android/obb');

/// Tags read from one file, plus the cover saved to the [CoverStore].
class ScannedFile {
  const ScannedFile({
    required this.file,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    this.coverId,
  });

  final FoundFile file;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int durationMs;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final String? coverId;
}

/// Reads tags and covers for [files]. Never throws for a single bad file:
/// unreadable tags fall back to the file name as title.
List<ScannedFile> readAudioFiles(List<FoundFile> files, String coversDir) {
  final covers = CoverStore(coversDir);
  // Cover id per directory for files without an embedded picture, so a
  // folder.jpg is hashed once per folder, not once per track.
  final folderCovers = <String, String?>{};

  String? folderCover(String dir) => folderCovers.putIfAbsent(dir, () {
    final image = CoverStore.findFolderImage(dir);
    if (image == null) return null;
    try {
      return covers.save(File(image).readAsBytesSync());
    } on FileSystemException {
      return null;
    }
  });

  return [for (final file in files) _readOne(file, covers, folderCover)];
}

ScannedFile _readOne(
  FoundFile file,
  CoverStore covers,
  String? Function(String dir) folderCover,
) {
  final tags = _readTags(File(file.path));

  String? coverId;
  if (tags.cover case (final bytes, final mime)?) {
    try {
      coverId = covers.save(bytes, mimeType: mime);
    } on FileSystemException {
      coverId = null;
    }
  }
  coverId ??= folderCover(p.dirname(file.path));

  // No title tag: "Artist - Title.mp3" file names are common.
  final fromName = MetadataCleanup.fromUpload(
    title: p.basenameWithoutExtension(file.path),
    uploader: '',
  );
  final artist = tags.artist ?? (tags.title == null ? fromName.artist : '');
  final title = tags.title == null
      ? fromName.title
      : _tidyTitle(tags.title!, artist);

  return ScannedFile(
    file: file,
    title: title.isEmpty ? p.basenameWithoutExtension(file.path) : title,
    artist: artist,
    album: tags.album ?? '',
    albumArtist: tags.albumArtist,
    durationMs: tags.duration?.inMilliseconds ?? 0,
    trackNumber: tags.trackNumber,
    discNumber: tags.discNumber,
    year: tags.year,
    genre: tags.genre,
    coverId: coverId,
  );
}

/// "Artist - Song (Official Music Video)" tagged with artist "Artist"
/// (typical for files from YouTube bots) becomes "Song".
String _tidyTitle(String title, String artist) {
  var t = title;
  if (artist.isNotEmpty) {
    final prefix = RegExp(
      '^${RegExp.escape(artist)}\\s+[-–—]\\s+',
      caseSensitive: false,
    );
    t = t.replaceFirst(prefix, '');
  }
  final cleaned = MetadataCleanup.stripNoise(t);
  return cleaned.isEmpty ? title : cleaned;
}

/// Tags from whichever reader can handle the file.
({
  String? title,
  String? artist,
  String? album,
  String? albumArtist,
  String? genre,
  int? year,
  int? trackNumber,
  int? discNumber,
  Duration? duration,
  (Uint8List, String?)? cover,
})
_readTags(File file) {
  try {
    final m = readMetadata(file, getImage: true);
    final pictures = m.pictures;
    final front = pictures.isEmpty
        ? null
        : pictures.firstWhere(
            (pic) => pic.pictureType == PictureType.coverFront,
            orElse: () => pictures.first,
          );
    return (
      title: _clean(m.title),
      artist: _clean(m.artist),
      album: _clean(m.album),
      albumArtist: _clean(m.albumArtist),
      genre: _clean(m.genres.firstOrNull),
      year: _plausibleYear(m.year?.year),
      trackNumber: m.trackNumber,
      discNumber: m.discNumber,
      duration: m.duration,
      cover: front == null ? null : (front.bytes, front.mimetype),
    );
  } catch (_) {
    // The tag library gives up on some valid files (see Mp4Tags); MP4 has a
    // fallback reader, anything else keeps the file with name-based info.
    final ext = p.extension(file.path).toLowerCase();
    final mp4 = (ext == '.m4a' || ext == '.mp4' || ext == '.aac')
        ? Mp4Tags.read(file)
        : null;
    return (
      title: _clean(mp4?.title),
      artist: _clean(mp4?.artist),
      album: _clean(mp4?.album),
      albumArtist: _clean(mp4?.albumArtist),
      genre: _clean(mp4?.genre),
      year: _plausibleYear(mp4?.year),
      trackNumber: mp4?.trackNumber,
      discNumber: mp4?.discNumber,
      duration: mp4?.duration,
      cover: mp4?.cover == null ? null : (mp4!.cover!, null),
    );
  }
}

/// Tags sometimes hold full dates the library misreads into absurd years.
int? _plausibleYear(int? year) =>
    year != null && year >= 1000 && year <= 2100 ? year : null;

/// Trims and drops empty strings and stray NUL terminators found in tags.
String? _clean(String? value) {
  final cleaned = value?.replaceAll('\u0000', '').trim();
  return (cleaned == null || cleaned.isEmpty) ? null : cleaned;
}
