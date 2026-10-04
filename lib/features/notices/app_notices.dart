import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/download/download_models.dart';
import '../../core/download/download_providers.dart';
import '../../core/download/download_queue.dart';
import '../../core/router/app_router.dart';
import '../../core/sync/sync_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../downloads/download_texts.dart';

/// Tells the user how background work ended, on whatever screen they are:
///  * downloads — once the queue is idle, one notice for the whole batch;
///  * sync — when tracks arrived from another device.
class AppNotices extends ConsumerStatefulWidget {
  const AppNotices({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppNotices> createState() => _AppNoticesState();
}

class _AppNoticesState extends ConsumerState<AppNotices> {
  /// Jobs of the current batch (queued or running since the queue was idle).
  final _batch = <int>{};
  StreamSubscription<Object?>? _syncReports;

  @override
  void initState() {
    super.initState();
    _syncReports = ref.read(syncServiceProvider).reports.listen((report) {
      if (!mounted) return;
      _show(
        AppLocalizations.of(context)
            .syncReceived(report.filesReceived, report.peer),
      );
    });
  }

  @override
  void dispose() {
    unawaited(_syncReports?.cancel());
    super.dispose();
  }

  void _onJobs(List<DownloadJob> jobs) {
    _batch.addAll([
      for (final j in jobs)
        if (j.isActive) j.id,
    ]);
    if (_batch.isEmpty || jobs.any((j) => j.isActive)) return;

    final finished = [
      for (final j in jobs)
        if (_batch.contains(j.id)) j,
    ];
    _batch.clear();
    final done = finished.where((j) => j.status == JobStatus.done).toList();
    final failed = finished.where((j) => j.status == JobStatus.failed).toList();
    final l10n = AppLocalizations.of(context);
    String name(DownloadJob j) =>
        '${j.candidate.artist} — ${j.candidate.title}';

    final text = switch ((done.length, failed.length)) {
      (0, 0) when finished.any((j) => j.status == JobStatus.skipped) =>
        l10n.jobSkipped,
      (0, 0) => null, // cancelled
      (1, 0) => l10n.noticeDownloaded(name(done.single)),
      (final n, 0) => l10n.noticeDownloadedMany(n),
      (0, 1) => l10n.noticeDownloadFailed(
        name(failed.single),
        l10n.failure(failed.single.failure ?? DownloadFailure.failed),
      ),
      (final d, final f) => l10n.noticeDownloadsMixed(d, f),
    };
    if (text != null) _show(text, openDownloads: failed.isNotEmpty);
  }

  void _show(String text, {bool openDownloads = false}) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: openDownloads
            ? SnackBarAction(
                label: l10n.noticeShow,
                onPressed: () => context.go(AppRoutes.downloads),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(downloadJobsProvider, (_, jobs) => _onJobs(jobs));
    return widget.child;
  }
}
