import 'dart:async';
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
