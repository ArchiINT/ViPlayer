import '../../core/download/download_models.dart';
import '../../core/download/download_queue.dart';
import '../../core/download/download_service.dart';
import '../../l10n/generated/app_localizations.dart';

/// User-facing texts for download states and failures.
extension DownloadTexts on AppLocalizations {
  String failure(DownloadFailure reason) => switch (reason) {
    DownloadFailure.unsupportedLink => failUnsupportedLink,
    DownloadFailure.notOnThisDevice => failNotOnThisDevice,
    DownloadFailure.alreadyInLibrary => jobSkipped,
    DownloadFailure.notFound => failNotFound,
    DownloadFailure.noMatch => failNoMatch,
    DownloadFailure.network => failNetwork,
    DownloadFailure.toolMissing => failToolMissing,
    DownloadFailure.failed => failFailed,
  };

  String jobStatus(DownloadJob job) => switch (job.status) {
    JobStatus.queued => jobQueued,
    JobStatus.running => switch (job.stage) {
      DownloadStage.matching => jobMatching,
      DownloadStage.tagging => jobTagging,
      DownloadStage.saving => jobSaving,
      DownloadStage.downloading || null => jobDownloading,
    },
    JobStatus.done => jobDone,
    JobStatus.skipped => jobSkipped,
    JobStatus.cancelled => jobCancelled,
    JobStatus.failed => [
      failure(job.failure ?? DownloadFailure.failed),
      if (job.failure == DownloadFailure.failed && job.error != null) job.error,
    ].join(': '),
  };
}

String serviceName(MusicService s) => switch (s) {
  MusicService.youtube => 'YouTube',
  MusicService.soundcloud => 'SoundCloud',
  MusicService.spotify => 'Spotify',
};
