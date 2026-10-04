import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/app_log.dart';
import 'download_models.dart';
import 'download_service.dart';

enum JobStatus { queued, running, done, skipped, failed, cancelled }

/// One track in the download queue.
@immutable
class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.candidate,
    this.status = JobStatus.queued,
    this.stage,
    this.progress,
    this.failure,
    this.error,
  });

  final int id;
  final DownloadCandidate candidate;
  final JobStatus status;
  final DownloadStage? stage;

  /// 0..1 while downloading; null when unknown.
  final double? progress;
  final DownloadFailure? failure;
  final String? error;

  bool get isActive =>
      status == JobStatus.queued || status == JobStatus.running;

  DownloadJob copyWith({
    JobStatus? status,
    DownloadStage? stage,
    double? progress,
    DownloadFailure? failure,
    String? error,
  }) => DownloadJob(
    id: id,
    candidate: candidate,
    status: status ?? this.status,
    stage: stage ?? this.stage,
    progress: progress,
    failure: failure,
    error: error,
  );
}

/// Runs downloads [maxParallel] at a time and reports every change through
/// [jobs] (newest first). Lives for the app session; finished downloads are
/// in the library, so the list itself is not persisted.
class DownloadQueue {
  DownloadQueue(this._service, {required this.format, this.maxParallel = 2});

  final DownloadService _service;

  /// Format for new downloads (read when a job starts).
  DownloadFormat Function() format;
  final int maxParallel;

  final _jobs = ValueNotifier<List<DownloadJob>>(const []);
  final _cancels = <int, Completer<void>>{};
  var _nextId = 0;
  var _running = 0;

  ValueListenable<List<DownloadJob>> get jobs => _jobs;

  void enqueue(List<DownloadCandidate> candidates) {
    final active = {
      for (final j in _jobs.value)
        if (j.isActive) j.candidate,
    };
    final added = [
      for (final c in candidates)
        if (!active.contains(c)) DownloadJob(id: _nextId++, candidate: c),
    ];
    if (added.isEmpty) return;
    _jobs.value = [...added.reversed, ..._jobs.value];
    _pump();
  }

  void cancel(int id) {
    final job = _find(id);
    if (job == null || !job.isActive) return;
    _cancels[id]?.complete();
    if (job.status == JobStatus.queued) {
      _update(id, (j) => j.copyWith(status: JobStatus.cancelled));
    }
  }

  void retry(int id) {
    final job = _find(id);
    if (job == null || job.isActive) return;
    _update(id, (j) => j.copyWith(status: JobStatus.queued));
    _pump();
  }

  /// Removes finished, failed and cancelled jobs from the list.
  void clearFinished() => _jobs.value = [
    for (final j in _jobs.value)
      if (j.isActive) j,
  ];

  void _pump() {
    while (_running < maxParallel) {
      // The list is newest-first, so the oldest waiting job is the last.
      final next = _jobs.value
          .where((j) => j.status == JobStatus.queued)
          .lastOrNull;
      if (next == null) return;
      unawaited(_run(next));
    }
  }

  Future<void> _run(DownloadJob job) async {
    _running++;
    final cancel = Completer<void>();
    _cancels[job.id] = cancel;
    _update(job.id, (j) => j.copyWith(status: JobStatus.running));
    try {
      await _service.download(
        job.candidate,
        format: format(),
        cancel: cancel,
        onProgress: (stage, progress) => _update(
          job.id,
          (j) => j.copyWith(stage: stage, progress: progress),
        ),
      );
      _update(job.id, (j) => j.copyWith(status: JobStatus.done));
    } on DownloadException catch (e) {
      final status = cancel.isCompleted
          ? JobStatus.cancelled
          : e.reason == DownloadFailure.alreadyInLibrary
          ? JobStatus.skipped
          : JobStatus.failed;
      _update(
        job.id,
        (j) => j.copyWith(status: status, failure: e.reason, error: e.detail),
      );
    } catch (e, stack) {
      AppLog.error('download ${job.candidate}', e, stack);
      _update(
        job.id,
        (j) => j.copyWith(
          status: JobStatus.failed,
          failure: DownloadFailure.failed,
          error: '$e',
        ),
      );
    } finally {
      _cancels.remove(job.id);
      _running--;
      _pump();
    }
  }

  DownloadJob? _find(int id) =>
      _jobs.value.where((j) => j.id == id).firstOrNull;

  void _update(int id, DownloadJob Function(DownloadJob) change) {
    _jobs.value = [for (final j in _jobs.value) j.id == id ? change(j) : j];
  }

  void dispose() {
    for (final c in _cancels.values) {
      if (!c.isCompleted) c.complete();
    }
    _jobs.dispose();
  }
}
