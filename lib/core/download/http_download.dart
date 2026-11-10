import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'download_models.dart';

/// Browser-like User-Agent: some services serve stripped pages otherwise.
const browserUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0 Safari/537.36';

/// GET returning the body as text; maps failures to [DownloadException].
Future<String> fetchText(
  http.Client client,
  Uri url, {
  Map<String, String> headers = const {},
}) async {
  final http.Response response;
  try {
    response = await client
        .get(url, headers: {'User-Agent': browserUserAgent, ...headers})
        .timeout(const Duration(seconds: 20));
  } on Exception catch (e) {
    throw DownloadException(DownloadFailure.network, '$e');
  }
  if (response.statusCode == 404) {
    throw const DownloadException(DownloadFailure.notFound);
  }
  if (response.statusCode >= 400) {
    throw DownloadException(
      DownloadFailure.network,
      'HTTP ${response.statusCode} for ${url.host}',
    );
  }
  return response.body;
}

/// Downloads [url] into [target] in one streamed request. Progress (0..1) is
/// reported when the server sends a Content-Length.
Future<void> downloadWhole(
  http.Client client,
  Uri url,
  File target, {
  void Function(double progress)? onProgress,
}) async {
  final request = http.Request('GET', url)
    ..headers['User-Agent'] = browserUserAgent;
  final http.StreamedResponse response;
  try {
    response = await client.send(request).timeout(const Duration(seconds: 30));
  } on Exception catch (e) {
    throw DownloadException(DownloadFailure.network, '$e');
  }
  if (response.statusCode >= 400) {
    throw DownloadException(
      DownloadFailure.network,
      'HTTP ${response.statusCode} for ${url.host}',
    );
  }
  final total = response.contentLength;
  final sink = target.openWrite();
  var received = 0;
  try {
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      sink.add(chunk);
      received += chunk.length;
      if (total != null && total > 0) onProgress?.call(received / total);
    }
  } on TimeoutException catch (e) {
    throw DownloadException(DownloadFailure.network, '$e');
  } finally {
    await sink.close();
  }
}

/// Downloads an HLS stream of fragmented MP4 (an init segment plus media
/// segments, as SoundCloud serves AAC) into [target] as one .m4a file.
/// Progress (0..1) is reported per segment.
Future<void> downloadHls(
  http.Client client,
  Uri playlist,
  File target, {
  void Function(double progress)? onProgress,
}) async {
  final text = await fetchText(client, playlist);
  final init = RegExp(r'#EXT-X-MAP:URI="([^"]+)"').firstMatch(text)?.group(1);
  final segments = <Uri>[];
  var seconds = 0.0;
  for (final line in LineSplitter.split(text)) {
    if (line.startsWith('#EXTINF:')) {
      seconds += double.tryParse(line.substring(8).split(',').first) ?? 0;
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      segments.add(playlist.resolve(line));
    }
  }
  if (init == null || segments.isEmpty || text.contains('#EXT-X-KEY')) {
    throw const DownloadException(
      DownloadFailure.failed,
      'unsupported stream format',
    );
  }

  final sink = target.openWrite();
  try {
    final head = await _fetchSegment(client, playlist.resolve(init));
    sink.add(_withDuration(head, seconds));
    // A few segments at a time: one by one is slow, all at once floods
    // the connection.
    const parallel = 4;
    for (var i = 0; i < segments.length; i += parallel) {
      final batch = await Future.wait([
        for (final s in segments.skip(i).take(parallel))
          _fetchSegment(client, s),
      ]);
      batch.forEach(sink.add);
      onProgress?.call((i + batch.length) / segments.length);
    }
  } finally {
    await sink.close();
  }
}

Future<Uint8List> _fetchSegment(http.Client client, Uri url) async {
  final http.Response response;
  try {
    response = await client
        .get(url, headers: {'User-Agent': browserUserAgent})
        .timeout(const Duration(seconds: 30));
  } on Exception catch (e) {
    throw DownloadException(DownloadFailure.network, '$e');
  }
  if (response.statusCode >= 400) {
    throw DownloadException(
      DownloadFailure.network,
      'HTTP ${response.statusCode} for ${url.host}',
    );
  }
  return response.bodyBytes;
}

/// Fragmented MP4 leaves the total duration in `mvhd` at 0 (it is spread
/// over the fragments); tag readers then report 0:00. Writes [seconds]
/// there when it is unset.
Uint8List _withDuration(Uint8List head, double seconds) {
  final at = _indexOf(head, latin1.encode('mvhd'));
  if (at < 0) return head;
  final init = Uint8List.fromList(head);
  final data = ByteData.sublistView(init);
  final body = at + 4;
  final v1 = init[body] == 1;
  final scaleAt = body + (v1 ? 20 : 12);
  final durationAt = scaleAt + 4;
  if (durationAt + (v1 ? 8 : 4) > init.length) return head;
  final scale = data.getUint32(scaleAt);
  final current = v1 ? data.getUint64(durationAt) : data.getUint32(durationAt);
  if (current != 0 || scale == 0) return head;
  final duration = (seconds * scale).round();
  if (v1) {
    data.setUint64(durationAt, duration);
  } else {
    data.setUint32(durationAt, duration.clamp(0, 0xFFFFFFFF));
  }
  return init;
}

int _indexOf(Uint8List bytes, List<int> pattern) {
  outer:
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Fetches a small binary resource (cover art). Null on any failure:
/// a missing cover never fails a download.
Future<Uint8List?> fetchBytes(http.Client client, Uri url) async {
  try {
    final response = await client
        .get(url, headers: {'User-Agent': browserUserAgent})
        .timeout(const Duration(seconds: 20));
    return response.statusCode == 200 ? response.bodyBytes : null;
  } on Exception {
    return null;
  }
}
