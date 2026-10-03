import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../download_models.dart';

/// Tags to write into a downloaded file.
class TrackTags {
  const TrackTags({
    required this.title,
    required this.artist,
    this.album,
    this.year,
    this.trackNumber,
    this.cover,
  });

  final String title;
  final String artist;
  final String? album;
  final int? year;
  final int? trackNumber;

  /// JPEG/PNG bytes; written as the front cover.
  final Uint8List? cover;

  factory TrackTags.of(DownloadCandidate c, Uint8List? cover) => TrackTags(
    title: c.title,
    artist: c.artist,
    album: c.album,
    year: c.year,
    trackNumber: c.trackNumber,
    cover: cover,
  );
}

/// Writes tags and cover art into downloaded files.
abstract interface class Tagger {
  Future<void> write(File file, TrackTags tags);
}

/// Desktop tagger on ffmpeg: every format, no re-encoding (streams are
/// copied), cover cropped to a square (YouTube thumbnails are 16:9).
class FfmpegTagger implements Tagger {
  const FfmpegTagger();

  static Future<bool> isAvailable() async =>
      (await Process.run('which', ['ffmpeg'])).exitCode == 0;

  @override
  Future<void> write(File file, TrackTags tags) async {
    final dir = await Directory.systemTemp.createTemp('viplayer_tag_');
    try {
      final ext = p.extension(file.path).toLowerCase();
      final out = p.join(dir.path, 'out$ext');
      File? cover;
      if (tags.cover != null) {
        cover = await _squareCover(tags.cover!, dir.path);
      }

      final text = <String, String>{
        'title': tags.title,
        'artist': tags.artist,
        'album': ?tags.album,
        'date': ?tags.year?.toString(),
        'track': ?tags.trackNumber?.toString(),
      };

      final List<String> args;
      if (ext == '.opus' || ext == '.ogg') {
        // Ogg cannot carry a picture stream; the cover goes into a
        // METADATA_BLOCK_PICTURE comment, passed via a metadata file.
        final meta = File(p.join(dir.path, 'meta.txt'));
        final buffer = StringBuffer(';FFMETADATA1\n');
        for (final MapEntry(:key, :value) in text.entries) {
          buffer.writeln('$key=${_escape(value)}');
        }
        if (cover != null) {
          buffer.writeln(
            'METADATA_BLOCK_PICTURE=${_flacPictureBlock(await cover.readAsBytes())}',
          );
        }
        await meta.writeAsString(buffer.toString());
        args = [
          '-i',
          file.path,
          '-i',
          meta.path,
          '-map',
          '0:a',
          '-map_metadata',
          '1',
          '-c',
          'copy',
          out,
        ];
      } else {
        args = [
          '-i',
          file.path,
          if (cover != null) ...['-i', cover.path],
          '-map',
          '0:a',
          if (cover != null) ...[
            '-map',
            '1:v',
            '-disposition:v:0',
            'attached_pic',
          ],
          '-c',
          'copy',
          if (ext == '.mp3') ...['-id3v2_version', '3'],
          for (final MapEntry(:key, :value) in text.entries) ...[
            '-metadata',
            '$key=$value',
          ],
          out,
        ];
      }

      final result = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-y',
        ...args,
      ]);
      if (result.exitCode != 0) {
        throw DownloadException(
          DownloadFailure.failed,
          'tagging failed: ${result.stderr}',
        );
      }
      await File(out).copy(file.path);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  static Future<File> _squareCover(Uint8List bytes, String dir) async {
    final source = File(p.join(dir, 'cover_source'));
    await source.writeAsBytes(bytes);
    final square = File(p.join(dir, 'cover.jpg'));
    final result = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-y',
      '-i',
      source.path,
      '-vf',
      "crop='min(iw,ih)':'min(iw,ih)',scale='min(800,iw)':-2",
      '-q:v',
      '3',
      square.path,
    ]);
    return result.exitCode == 0 ? square : source;
  }

  /// ffmetadata escaping: = ; # \ and newlines.
  static String _escape(String value) =>
      value.replaceAllMapped(RegExp(r'[=;#\\\n]'), (m) => '\\${m.group(0)}');

  /// Base64 FLAC picture block (type 3 = front cover), the standard way to
  /// store cover art in Vorbis comments.
  static String _flacPictureBlock(Uint8List image) {
    final mime = utf8.encode(
      image.length > 3 && image[0] == 0x89 ? 'image/png' : 'image/jpeg',
    );
    final data = BytesBuilder()
      ..add(_u32(3))
      ..add(_u32(mime.length))
      ..add(mime)
      ..add(_u32(0)) // description
      ..add(_u32(0)) // width  (0 = unknown)
      ..add(_u32(0)) // height
      ..add(_u32(0)) // colour depth
      ..add(_u32(0)) // palette size
      ..add(_u32(image.length))
      ..add(image);
    return base64Encode(data.toBytes());
  }

  static List<int> _u32(int v) => [
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  ];
}

/// Pure-Dart tagger for MP3 / M4A (Android, where ffmpeg is not bundled).
class DartTagger implements Tagger {
  const DartTagger();

  @override
  Future<void> write(File file, TrackTags tags) async {
    try {
      updateMetadata(file, (metadata) {
        metadata.setTitle(tags.title);
        metadata.setArtist(tags.artist);
        if (tags.album != null) metadata.setAlbum(tags.album!);
        if (tags.year != null) metadata.setYear(DateTime(tags.year!));
        if (tags.trackNumber != null) {
          metadata.setTrackNumber(tags.trackNumber!);
        }
        if (tags.cover != null) {
          metadata.setPictures([
            Picture(tags.cover!, 'image/jpeg', PictureType.coverFront),
          ]);
        }
      });
    } catch (e) {
      throw DownloadException(DownloadFailure.failed, 'tagging failed: $e');
    }
  }
}
