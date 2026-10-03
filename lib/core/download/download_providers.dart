import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../library/library_providers.dart';
import '../platform/app_directories.dart';
import '../settings/settings_providers.dart';
import 'download_models.dart';
import 'download_queue.dart';
import 'download_service.dart';
import 'tools/tagger.dart';
import 'tools/ytdlp.dart';

/// Desktop builds download through yt-dlp + ffmpeg; Android uses the
/// pure-Dart path (SoundCloud only — see docs/DOWNLOADS.md).
final _isDesktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final ytDlpProvider = Provider<YtDlp?>(
  (ref) => _isDesktop
      ? YtDlp(
          binDirectory: p.join(
            ref.watch(appDirectoriesProvider).support,
            'bin',
          ),
        )
      : null,
);

/// yt-dlp version, or null when it is missing (desktop only).
final ytDlpVersionProvider = FutureProvider<String?>(
  (ref) async => ref.watch(ytDlpProvider)?.version(),
);

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final scanner = ref.watch(libraryScannerProvider);
  final service = DownloadService(
    client: ref.watch(httpClientProvider),
    downloadDirectory: ref.watch(appDirectoriesProvider).downloads,
    library: ref.watch(libraryRepositoryProvider),
    importFile: scanner.importFile,
    tagger: _isDesktop ? const FfmpegTagger() : const DartTagger(),
    ytdlp: ref.watch(ytDlpProvider),
  );
  ref.onDispose(service.close);
  return service;
});

/// Formats offered on this device.
final availableFormatsProvider = Provider<List<DownloadFormat>>(
  (ref) => _isDesktop ? DownloadFormat.values : const [DownloadFormat.m4a],
);

final downloadQueueProvider = Provider<DownloadQueue>((ref) {
  final queue = DownloadQueue(
    ref.watch(downloadServiceProvider),
    format: () {
      final wanted = ref.read(settingsProvider).downloadFormat;
      return ref.read(availableFormatsProvider).contains(wanted)
          ? wanted
          : DownloadFormat.m4a;
    },
  );
  ref.onDispose(queue.dispose);
  return queue;
});

final downloadJobsProvider =
    NotifierProvider<DownloadJobsNotifier, List<DownloadJob>>(
      DownloadJobsNotifier.new,
    );

class DownloadJobsNotifier extends Notifier<List<DownloadJob>> {
  @override
  List<DownloadJob> build() {
    final jobs = ref.watch(downloadQueueProvider).jobs;
    void listener() => state = jobs.value;
    jobs.addListener(listener);
    ref.onDispose(() => jobs.removeListener(listener));
    return jobs.value;
  }
}
