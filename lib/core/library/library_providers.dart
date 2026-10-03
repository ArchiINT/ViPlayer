import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../platform/app_directories.dart';
import '../settings/settings_providers.dart';
import 'audio_files.dart';
import 'cover_store.dart';
import 'library_models.dart';
import 'library_repository.dart';
import 'library_scanner.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final dirs = ref.watch(appDirectoriesProvider);
  return LibraryRepository(
    ref.watch(appDatabaseProvider),
    CoverStore(dirs.covers),
  );
});

final libraryScannerProvider = Provider<LibraryScanner>((ref) {
  final dirs = ref.watch(appDirectoriesProvider);
  return LibraryScanner(
    ref.watch(appDatabaseProvider),
    coversDir: dirs.covers,
    downloadDir: dirs.downloads,
  );
});

/// Tracks with a file on this device; updates live as the database changes.
///
/// Throttled: a scan commits a batch every few milliseconds, and each update
/// rebuilds the whole library index and visible lists. The first and the last
/// value always come through.
final libraryTracksProvider = StreamProvider<List<LibraryTrack>>(
  (ref) => _throttleLatest(
    ref.watch(libraryRepositoryProvider).watchTracks(),
    const Duration(milliseconds: 400),
  ),
);

/// Emits the first event at once, then at most one event per [interval] —
/// always the most recent one, so the final state is never lost.
Stream<T> _throttleLatest<T>(Stream<T> source, Duration interval) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? timer;
  T? pending;
  var hasPending = false;
  var sourceDone = false;

  void flush() {
    timer = null;
    if (hasPending) {
      hasPending = false;
      controller.add(pending as T);
      timer = Timer(interval, flush);
    } else if (sourceDone) {
      unawaited(controller.close());
    }
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (event) {
          if (timer == null) {
            controller.add(event);
            timer = Timer(interval, flush);
          } else {
            pending = event;
            hasPending = true;
          }
        },
        onError: controller.addError,
        onDone: () {
          sourceDone = true;
          if (timer == null) unawaited(controller.close());
        },
      );
    },
    onCancel: () async {
      timer?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}

/// Albums/artists/search index derived from [libraryTracksProvider].
final libraryIndexProvider = Provider<AsyncValue<LibraryIndex>>(
  (ref) => ref.watch(libraryTracksProvider).whenData(LibraryIndex.build),
);

final libraryFoldersProvider = StreamProvider<List<LibraryFolderRow>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchFolders(),
);

@immutable
class ScanState {
  const ScanState({this.running = false, this.progress, this.last, this.error});

  final bool running;
  final ScanProgress? progress;
  final ScanResult? last;
  final Object? error;
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);

/// Runs library scans one at a time and keeps the library fresh:
///  * scans at startup and whenever folders or settings change;
///  * on desktop, watches every library directory and rescans shortly after
///    files appear, change or disappear.
class ScanController extends Notifier<ScanState> {
  /// Batch bursts of file events (copying an album) into one rescan.
  static const _watchDebounce = Duration(seconds: 2);

  /// Upper bound on watched directories (each costs an inotify watch).
  static const _maxWatchedDirectories = 4000;

  /// Max rate of progress updates reaching the UI.
  static const _progressInterval = Duration(milliseconds: 100);

  final _watchers = <StreamSubscription<FileSystemEvent>>[];
  DateTime _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _debounce;
  bool _rerunRequested = false;

  @override
  ScanState build() {
    ref.onDispose(_dispose);
    return const ScanState();
  }

  /// Starts a scan. If one is already running, another runs right after it,
  /// so changes made during a scan are never missed.
  Future<void> rescan() async {
    if (state.running) {
      _rerunRequested = true;
      return;
    }
    state = ScanState(running: true, last: state.last);
    try {
      final result = await ref
          .read(libraryScannerProvider)
          .scan(
            includeDeviceMusic: ref.read(settingsProvider).scanDeviceMusic,
            onProgress: (progress) {
              // Throttled: every update rebuilds listeners, and a scan can
              // report hundreds of steps per second.
              final now = DateTime.now();
              final isLast =
                  progress.total > 0 && progress.done == progress.total;
              if (!isLast &&
                  now.difference(_lastProgressAt) < _progressInterval) {
                return;
              }
              _lastProgressAt = now;
              if (ref.mounted) {
                state = ScanState(
                  running: true,
                  progress: progress,
                  last: state.last,
                );
              }
            },
          );
      if (!ref.mounted) return;
      state = ScanState(last: result);
      _watch(result.directories);
    } catch (error, stack) {
      debugPrint('Library scan failed: $error\n$stack');
      if (ref.mounted) state = ScanState(last: state.last, error: error);
    }

    if (_rerunRequested && ref.mounted) {
      _rerunRequested = false;
      await rescan();
    }
  }

  // Dart's recursive directory watching is not available on Linux, so each
  // directory gets its own (non-recursive) watcher.
  void _watch(List<String> directories) {
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) return;
    _cancelWatchers();
    for (final dir in directories.take(_maxWatchedDirectories)) {
      try {
        _watchers.add(
          Directory(dir).watch().listen(_onFileEvent, onError: (_) {}),
        );
      } on FileSystemException {
        // Directory vanished between scan and watch; next scan handles it.
      }
    }
  }

  void _onFileEvent(FileSystemEvent event) {
    final relevant = event.isDirectory || isAudioPath(event.path);
    if (!relevant) return;
    _debounce?.cancel();
    _debounce = Timer(_watchDebounce, rescan);
  }

  void _cancelWatchers() {
    for (final w in _watchers) {
      unawaited(w.cancel());
    }
    _watchers.clear();
  }

  void _dispose() {
    _debounce?.cancel();
    _cancelWatchers();
  }
}
