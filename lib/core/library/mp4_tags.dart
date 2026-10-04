import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Tags of an MP4/M4A file, read by [Mp4Tags.read].
class Mp4TagValues {
  String? title;
  String? artist;
  String? album;
  String? albumArtist;
  String? genre;
  int? year;
  int? trackNumber;
  int? discNumber;
  Duration? duration;
  Uint8List? cover;
}

/// Minimal reader for iTunes-style MP4 tags (`moov/udta/meta/ilst`).
///
/// A fallback for files the main tag library rejects — notably files saved
/// by yt-dlp / Telegram bots, whose `©day` is a full date like `20170727`,
/// which makes audio_metadata_reader 1.8 throw and lose every tag.
/// Only reads; never throws for malformed input (returns what it found).
abstract final class Mp4Tags {
  static Mp4TagValues? read(File file) {
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      final moov = _findTopLevel(raf, 'moov');
      if (moov == null) return null;
      final values = Mp4TagValues();
      _walk(moov, 0, moov.length, values, const ['moov']);
      return values;
    } on Object {
      return null;
    } finally {
      raf?.closeSync();
    }
  }

  /// Reads the body of the first top-level box of [type] (moov is small;
  /// mdat, which holds the audio, is skipped without reading).
  static Uint8List? _findTopLevel(RandomAccessFile raf, String type) {
    final length = raf.lengthSync();
    var offset = 0;
    while (offset + 8 <= length) {
      raf.setPositionSync(offset);
      final header = raf.readSync(16);
      if (header.length < 8) return null;
      var size = _u32(header, 0);
      final name = latin1.decode(header.sublist(4, 8));
      var headerSize = 8;
      if (size == 1 && header.length >= 16) {
        size = _u32(header, 8) * 0x100000000 + _u32(header, 12);
        headerSize = 16;
      } else if (size == 0) {
        size = length - offset;
      }
      if (size < headerSize) return null;
      if (name == type) {
        raf.setPositionSync(offset + headerSize);
        return raf.readSync(size - headerSize);
      }
      offset += size;
    }
    return null;
  }

  static void _walk(
    Uint8List buf,
    int start,
    int end,
    Mp4TagValues out,
    List<String> path,
  ) {
    var offset = start;
    while (offset + 8 <= end) {
      final size = _u32(buf, offset);
      if (size < 8 || offset + size > end) return;
      final name = latin1.decode(buf.sublist(offset + 4, offset + 8));
      final bodyStart = offset + 8;
      final bodyEnd = offset + size;

      switch (name) {
        case 'mvhd':
          out.duration ??= _mvhdDuration(buf, bodyStart);
        case 'udta' || 'ilst':
          _walk(buf, bodyStart, bodyEnd, out, [...path, name]);
        case 'meta':
          // meta is a "full box": 4 bytes of version/flags first.
          _walk(buf, bodyStart + 4, bodyEnd, out, [...path, name]);
        default:
          if (path.isNotEmpty && path.last == 'ilst') {
            _readItem(name, buf, bodyStart, bodyEnd, out);
          }
      }
      offset += size;
    }
  }

  /// An ilst item holds a `data` box: type(4) locale(4) payload.
  static void _readItem(
    String name,
    Uint8List buf,
    int start,
    int end,
    Mp4TagValues out,
  ) {
    if (start + 16 > end ||
        latin1.decode(buf.sublist(start + 4, start + 8)) != 'data') {
      return;
    }
    final dataSize = _u32(buf, start);
    final payload = buf.sublist(start + 16, (start + dataSize).clamp(0, end));
    String text() => utf8.decode(payload, allowMalformed: true).trim();
    switch (name) {
      case '©nam':
        out.title = text();
      case '©ART':
        out.artist = text();
      case '©alb':
        out.album = text();
      case 'aART':
        out.albumArtist = text();
      case '©gen':
        out.genre = text();
      case '©day':
        // "2017", "2017-07-27" or yt-dlp's "20170727": the year leads.
        out.year = int.tryParse(text().padRight(4).substring(0, 4).trim());
      case 'trkn' when payload.length >= 4:
        out.trackNumber = (payload[2] << 8) | payload[3];
      case 'disk' when payload.length >= 4:
        out.discNumber = (payload[2] << 8) | payload[3];
      case 'covr':
        out.cover = Uint8List.fromList(payload);
    }
  }

  static Duration? _mvhdDuration(Uint8List buf, int start) {
    final version = buf[start];
    if (version == 1) {
      final scale = _u32(buf, start + 20);
      final duration =
          _u32(buf, start + 24) * 0x100000000 + _u32(buf, start + 28);
      return scale == 0
          ? null
          : Duration(milliseconds: duration * 1000 ~/ scale);
    }
    final scale = _u32(buf, start + 12);
    final duration = _u32(buf, start + 16);
    return scale == 0 ? null : Duration(milliseconds: duration * 1000 ~/ scale);
  }

  static int _u32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
}
