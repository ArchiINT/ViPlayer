import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/empty_state.dart';

/// The two download flows are kept separate on purpose (see docs/ROADMAP.md).
enum DownloadMode { byLink, byName }

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadMode _mode = DownloadMode.byLink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navDownloads)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<DownloadMode>(
                segments: [
                  ButtonSegment(
                    value: DownloadMode.byLink,
                    icon: const Icon(Icons.link),
                    label: Text(l10n.downloadsByLink),
                  ),
                  ButtonSegment(
                    value: DownloadMode.byName,
                    icon: const Icon(Icons.search),
                    label: Text(l10n.downloadsByName),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.download_outlined,
              title: l10n.downloadsEmptyTitle,
              message: l10n.downloadsEmptyBody,
            ),
          ),
        ],
      ),
    );
  }
}
