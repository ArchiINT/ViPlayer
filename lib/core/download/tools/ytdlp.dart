import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../download_models.dart';
import '../http_download.dart';

/// yt-dlp, the desktop download engine (YouTube, SoundCloud and hundreds of
/// other sites). Formats are chosen so audio is never re-encoded except for
/// MP3.
///
/// Binary lookup: ViPlayer's own copy in `<support>/bin/yt-dlp` (installed
/// and updated from Settings — services break old versions quickly, and a
/// distro package cannot be updated from inside the app), else `yt-dlp` on
/// PATH.
class YtDlp {
  YtDlp({required this.binDirectory});

  final String binDirectory;

  static const _releaseUrl =
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp';

  String get _ownBinary => p.join(binDirectory, 'yt-dlp');

  Future<String?> _binary() async {
    if (File(_ownBinary).existsSync()) return _ownBinary;
    final which = await Process.run('which', ['yt-dlp']);
    final path = (which.stdout as String).trim();
    return which.exitCode == 0 && path.isNotEmpty ? path : null;
  }

  /// Installed version, or null if yt-dlp is not available.
  Future<String?> version() async {
    final bin = await _binary();
    if (bin == null) return null;
    final result = await Process.run(bin, ['--version']);
    return result.exitCode == 0 ? (result.stdout as String).trim() : null;
  }

  /// True when the app manages its own copy (then [update] uses `-U`).
  bool get hasOwnCopy => File(_ownBinary).existsSync();

  /// Installs or updates ViPlayer's own copy to the latest release.
  /// Returns the new version.
  Future<String?> update(http.Client client) async {
    if (hasOwnCopy) {
      await Process.run(_ownBinary, ['-U']);
      return version();
    }
    await Directory(binDirectory).create(recursive: true);
    final temp = File('$_ownBinary.part');
    await downloadWhole(client, Uri.parse(_releaseUrl), temp);
    await Process.run('chmod', ['+x', temp.path]);
    await temp.rename(_ownBinary);
    return version();
  }

  /// Downloads the audio of [url] into [directory] and returns the file.
  /// Never re-encodes m4a / opus; mp3 is converted with ffmpeg.
  /// Cancel with [cancel].
  Future<File> download(
    String url, {
    required DownloadFormat format,
    required String directory,
    void Function(double progress)? onProgress,
    Completer<void>? cancel,
  }) async {
    final bin = await _binary();
    if (bin == null) {
      throw const DownloadException(DownloadFailure.toolMissing, 'yt-dlp');
    }
    final args = [
      '--no-playlist',
      '--no-warnings',
      '--no-mtime',
      '--newline',
      '--progress-template',
      'download:VP %(progress.downloaded_bytes)s %(progress.total_bytes)s '
          '%(progress.total_bytes_estimate)s',
      ...switch (format) {
        DownloadFormat.m4a => [
          '-f',
          'bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio',
          '-x',
          '--audio-format',
          'm4a',
        ],
        DownloadFormat.opus => [
          '-f',
          'bestaudio[acodec=opus]/bestaudio',
          '-x',
          '--audio-format',
          'opus',
        ],
        DownloadFormat.mp3 => [
          '-f',
          'bestaudio',
          '-x',
          '--audio-format',
          'mp3',
          '--audio-quality',
          '0',
        ],
      },
      '-o',
      p.join(directory, '%(id)s.%(ext)s'),
      '--print',
      'after_move:VPFILE %(filepath)s',
      url,
    ];

    final process = await Process.start(bin, args);
    unawaited(cancel?.future.then((_) => process.kill()));

    String? file;
    final errors = StringBuffer();
    final out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('VPFILE ')) {
            file = line.substring(7).trim();
          } else if (line.startsWith('VP ')) {
            final parts = line.split(' ');
            final done = double.tryParse(parts[1]);
            final total =
                double.tryParse(parts[2]) ?? double.tryParse(parts[3]);
            if (done != null && total != null && total > 0) {
              onProgress?.call((done / total).clamp(0, 1));
            }
          }
        });
    final err = process.stderr.transform(utf8.decoder).listen(errors.write);

    final exitCode = await process.exitCode;
    await out.cancel();
    await err.cancel();

    if (cancel?.isCompleted ?? false) {
      throw const DownloadException(DownloadFailure.failed, 'cancelled');
    }
    if (exitCode != 0 || file == null) {
      throw DownloadException(DownloadFailure.failed, _summarize(errors));
    }
    return File(file!);
  }

  /// The most useful line of yt-dlp's error output.
  static String _summarize(StringBuffer stderr) {
    final lines = stderr
        .toString()
        .split('\n')
        .where((l) => l.startsWith('ERROR'))
        .toList();
    return lines.isEmpty
        ? 'yt-dlp failed'
        : lines.last.replaceFirst('ERROR: ', '');
  }
}
