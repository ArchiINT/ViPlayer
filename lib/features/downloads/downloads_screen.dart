import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_providers.dart';
import '../../core/download/download_queue.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_panel.dart';
import '../../shared/widgets/section_header.dart';
import 'widgets/job_tile.dart';
import 'widgets/link_panel.dart';

/// The two download flows are kept separate on purpose (see docs/ROADMAP.md).
enum DownloadMode { byLink, byName }

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  DownloadMode _mode = DownloadMode.byLink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final jobs = ref.watch(downloadJobsProvider);
    final canYoutube = ref.watch(downloadServiceProvider).canDownloadYoutube;
    final hasFinished = jobs.any((j) => !j.isActive);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navDownloads)),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverList.list(
              children: [
                SegmentedButton<DownloadMode>(
                  segments: [
                    ButtonSegment(
                      value: DownloadMode.byLink,
                      icon: const Icon(Icons.link_rounded),
                      label: Text(l10n.downloadsByLink),
                    ),
                    ButtonSegment(
                      value: DownloadMode.byName,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(l10n.downloadsByName),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 16),
                if (_mode == DownloadMode.byLink) ...[
                  if (!canYoutube) ...[
                    Text(
                      l10n.phoneDownloadsNote,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const LinkPanel(),
                ] else
                  Text(
                    l10n.downloadsByNameSoon,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          if (jobs.isEmpty)
            // A plain box, not SliverFillRemaining: with a link preview
            // open there may be little room left, and it must not overflow.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: Icons.download_outlined,
                  title: l10n.downloadsEmptyTitle,
                  message: l10n.downloadsEmptyBody,
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(child: SectionHeader(l10n.downloadsQueue)),
                  if (hasFinished)
                    Padding(
                      padding: const EdgeInsets.only(right: 12, top: 14),
                      child: TextButton(
                        onPressed: ref
                            .read(downloadQueueProvider)
                            .clearFinished,
                        child: Text(l10n.clearFinished),
                      ),
                    ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverToBoxAdapter(
                child: GlassGroup(children: [for (final j in jobs) _keyed(j)]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _keyed(DownloadJob j) => JobTile(key: ValueKey(j.id), job: j);
}
