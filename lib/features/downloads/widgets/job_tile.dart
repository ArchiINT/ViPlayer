import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/download_providers.dart';
import '../../../core/download/download_queue.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../download_texts.dart';
import 'remote_cover.dart';

/// One download in the queue: cover, title, status / progress, and
/// cancel or retry.
class JobTile extends ConsumerWidget {
  const JobTile({super.key, required this.job});

  final DownloadJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.read(downloadQueueProvider);
    final c = job.candidate;
    final accent = Theme.of(context).colorScheme.primary;

    final (IconData? icon, Color color) = switch (job.status) {
      JobStatus.done => (Icons.check_circle_rounded, accent),
      JobStatus.skipped => (
        Icons.check_circle_outline_rounded,
        AppColors.textSecondary,
      ),
      JobStatus.failed => (Icons.error_outline_rounded, AppColors.error),
      JobStatus.cancelled => (Icons.block_rounded, AppColors.textTertiary),
      _ => (null, AppColors.textSecondary),
    };

    return ListTile(
      // Room for the progress bar / a two-line error under the title.
      isThreeLine:
          job.status == JobStatus.running || job.status == JobStatus.failed,
      leading: RemoteCover(url: c.coverUrl, size: 44),
      title: Text(
        '${c.artist} — ${c.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.jobStatus(job),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12),
          ),
          if (job.status == JobStatus.running) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: job.progress, minHeight: 3),
          ],
        ],
      ),
      trailing: switch (job.status) {
        JobStatus.queued || JobStatus.running => IconButton(
          tooltip: l10n.cancel,
          onPressed: () => queue.cancel(job.id),
          icon: const Icon(Icons.close_rounded),
        ),
        JobStatus.failed || JobStatus.cancelled => IconButton(
          tooltip: l10n.retry,
          onPressed: () => queue.retry(job.id),
          icon: const Icon(Icons.refresh_rounded),
        ),
        _ => Icon(icon, color: color),
      },
    );
  }
}
