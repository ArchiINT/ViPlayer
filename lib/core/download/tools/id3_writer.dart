import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tagger.dart';

/// Writes an ID3v2.3 tag (title, artist, album, year, track, front cover)
/// at the start of an MP3, replacing any existing ID3v2 tag. The audio is
/// copied unchanged.
///
/// Written in-house because audio_metadata_reader 1.8 writes nothing to MP3s
/// that have no ID3 tag yet — which is how SoundCloud serves many files.
abstract final class Id3Writer {
  static Future<void> write(File file, TrackTags tags) async {
    final bytes = await file.readAsBytes();
    final audio = bytes.sublist(_existingTagLength(bytes));

    final frames = BytesBuilder()
      ..add(_text('TIT2', tags.title))
      ..add(_text('TPE1', tags.artist));
    if (tags.album case final album? when album.isNotEmpty) {
      frames.add(_text('TALB', album));
    }
    if (tags.year case final year?) frames.add(_text('TYER', '$year'));
    if (tags.trackNumber case final n?) frames.add(_text('TRCK', '$n'));
    if (tags.cover case final cover?) frames.add(_picture(cover));
    final body = frames.toBytes();

    final out = BytesBuilder()
      ..add(ascii.encode('ID3'))
      ..add([3, 0, 0]) // v2.3.0, no flags
      ..add(_syncSafe(body.length))
      ..add(body)
      ..add(audio);
    final temp = File('${file.path}.tagging');
    await temp.writeAsBytes(out.toBytes(), flush: true);
    await temp.rename(file.path);
  }

  /// Length of an ID3v2 tag at the start of [bytes] (0 if none).
  static int _existingTagLength(Uint8List bytes) {
    if (bytes.length < 10 ||
        ascii.decode(bytes.sublist(0, 3), allowInvalid: true) != 'ID3') {
      return 0;
    }
    final size =
        (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
    final hasFooter = bytes[5] & 0x10 != 0;
    final total = 10 + size + (hasFooter ? 10 : 0);
    return total <= bytes.length ? total : 0;
  }

  /// Text frame, UTF-16 with BOM (encoding 1) so any script survives.
  static Uint8List _text(String id, String value) {
    final payload = BytesBuilder()
      ..addByte(1)
      ..add([0xFF, 0xFE]);
    for (final unit in value.codeUnits) {
      payload.add([unit & 0xFF, unit >> 8]);
    }
    return _frame(id, payload.toBytes());
  }

  static Uint8List _picture(Uint8List image) {
    final isPng = image.length > 3 && image[0] == 0x89 && image[1] == 0x50;
    final payload = BytesBuilder()
      ..addByte(0) // ISO-8859-1 for mime and description
      ..add(ascii.encode(isPng ? 'image/png' : 'image/jpeg'))
      ..addByte(0)
      ..addByte(3) // front cover
      ..addByte(0) // empty description
      ..add(image);
    return _frame('APIC', payload.toBytes());
  }

  static Uint8List _frame(String id, Uint8List payload) {
    final size = payload.length;
    return (BytesBuilder()
          ..add(ascii.encode(id))
          ..add([
            size >> 24 & 0xFF,
            size >> 16 & 0xFF,
            size >> 8 & 0xFF,
            size & 0xFF,
          ])
          ..add([0, 0]) // frame flags
          ..add(payload))
        .toBytes();
  }

  static List<int> _syncSafe(int n) => [
    n >> 21 & 0x7F,
    n >> 14 & 0x7F,
    n >> 7 & 0x7F,
    n & 0x7F,
  ];
}
