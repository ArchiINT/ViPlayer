import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Stores cover images on disk, named by a hash of their content: tracks of
/// one album share a single file, and re-scanning never duplicates covers.
///
/// Pure dart:io — safe to use inside background isolates.
class CoverStore {
  const CoverStore(this.directory);

  final String directory;

  /// File names checked next to audio files when they have no embedded cover.
  static const folderImageNames = [
    'cover.jpg',
    'cover.png',
    'folder.jpg',
    'folder.png',
    'front.jpg',
    'front.png',
    'album.jpg',
    'album.png',
  ];

  String pathFor(String coverId) => p.join(directory, coverId);

  /// Saves [bytes] (if not stored yet) and returns the cover id.
  String save(Uint8List bytes, {String? mimeType}) {
    final hash = sha1.convert(bytes).toString().substring(0, 24);
    final id = '$hash.${_extension(bytes, mimeType)}';
    final file = File(pathFor(id));
    if (!file.existsSync()) file.writeAsBytesSync(bytes, flush: false);
    return id;
  }

  /// Returns the path of a cover image lying in [directory], if any.
  /// Matching is case-insensitive (Cover.JPG counts too).
  static String? findFolderImage(String directory) {
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(directory).listSync(followLinks: false);
    } on FileSystemException {
      return null;
    }
    final byLowerName = {
      for (final e in entries)
        if (e is File) p.basename(e.path).toLowerCase(): e.path,
    };
    for (final name in folderImageNames) {
      final path = byLowerName[name];
      if (path != null) return path;
    }
    return null;
  }

  static String _extension(Uint8List bytes, String? mimeType) {
    // Magic numbers first — tag mime types are frequently wrong.
    if (bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    if (bytes.length > 12 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    return switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
  }
}
