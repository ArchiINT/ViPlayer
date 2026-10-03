import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/download_models.dart';
import '../../../core/download/download_providers.dart';
import '../../../core/download/download_service.dart';
import '../../../core/player/preview_player.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/section_header.dart';
import '../download_texts.dart';
import 'remote_cover.dart';

/// "By name": search, listen to results, tick the ones to download.
class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final _controller = TextEditingController();
  bool _loading = false;
  String _query = '';
  Map<MusicService, SearchOutcome> _results = const {};
  MusicService? _filter; // null = all sources
  final _selected = <DownloadCandidate>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _query = query;
      _selected.clear();
    });
    final results = await ref
        .read(downloadServiceProvider)
        .search(query, services: _services());
    if (!mounted || _query != query) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  /// Sources to search: what this device downloads itself, plus YouTube
  /// when a PC at home can download it for us.
  List<MusicService> _services() {
    final own = ref.read(downloadServiceProvider).searchableServices;
    final helper = ref.read(syncServiceProvider).downloadPeer;
    return [
      if (helper != null && !own.contains(MusicService.youtube))
        MusicService.youtube,
      ...own,
    ];
  }

  Future<void> _downloadSelected() async {
    final service = ref.read(downloadServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await ref.read(previewPlayerProvider).stop();
    final local = [
      for (final c in _selected)
        if (service.supports(c.service)) c,
    ];
    final remote = [
      for (final c in _selected)
        if (!service.supports(c.service)) c,
    ];
    ref.read(downloadQueueProvider).enqueue(local);
    if (remote.isNotEmpty) {
      final sync = ref.read(syncServiceProvider);
      final peerId = sync.downloadPeer;
      if (peerId != null) {
        await sync.remoteDownload(peerId, remote);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.sentToDevice(sync.snapshot.value.paired[peerId]!.name),
            ),
          ),
        );
      }
    }
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.watch(syncSnapshotProvider.select((s) => s.nearby.length));
    final services = _services();
    final shown = [
      for (final s in services)
        if (_filter == null || _filter == s) s,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onSubmitted: (_) => _search(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.searchByNameHint,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: l10n.find,
              onPressed: _search,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
        if (services.length > 1) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.sourceAll),
                selected: _filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              for (final s in services)
                ChoiceChip(
                  label: Text(serviceName(s)),
                  selected: _filter == s,
                  onSelected: (_) => setState(() => _filter = s),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: AppMotion.normal,
          child: _selected.isEmpty
              ? const SizedBox(width: double.infinity)
              : FilledButton.icon(
                  onPressed: _downloadSelected,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(l10n.downloadSelected(_selected.length)),
                ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          )
        else if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              services.length > 1
                  ? l10n.searchByNameEmpty
                  : l10n.searchByNameEmptyPhone,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          for (final s in shown)
            if (_results[s] case final outcome?) ...[
              SectionHeader(serviceName(s)),
              if (outcome.failure != null)
                Text(
                  l10n.serviceUnavailable(serviceName(s)),
                  style: const TextStyle(color: AppColors.textSecondary),
                )
              else if (outcome.items.isEmpty)
                Text(
                  l10n.searchNoResults(_query),
                  style: const TextStyle(color: AppColors.textSecondary),
                )
              else
                GlassPanel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final c in outcome.items)
                        _ResultTile(
                          key: ValueKey(PreviewPlayer.keyOf(c)),
                          candidate: c,
                          selected: _selected.contains(c),
                          onSelected: (v) => setState(
                            () => v ? _selected.add(c) : _selected.remove(c),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onSelected,
  });

  final DownloadCandidate candidate;
  final bool selected;
  final void Function(bool) onSelected;

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    return InkWell(
      onTap: () => onSelected(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            _PreviewButton(candidate: c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    c.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatTrackDuration(c.durationMs),
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
            Checkbox(value: selected, onChanged: (v) => onSelected(v ?? false)),
          ],
        ),
      ),
    );
  }
}

/// Cover with a play/pause overlay and a ring showing the preview position.
/// Only this widget rebuilds while a preview plays.
class _PreviewButton extends ConsumerWidget {
  const _PreviewButton({required this.candidate});

  final DownloadCandidate candidate;
  static const _size = 52.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = PreviewPlayer.keyOf(candidate);
    final state = ref.watch(
      previewStateProvider.select((s) => s.key == key ? s : null),
    );
    final accent = Theme.of(context).colorScheme.primary;
    final playing = state?.playing ?? false;

    return Tooltip(
      message: playing ? l10n.stopListening : l10n.listen,
      child: GestureDetector(
        onTap: () => ref.read(previewPlayerProvider).toggle(candidate, () {
          final service = ref.read(downloadServiceProvider);
          if (service.supports(candidate.service)) {
            return service.preview(candidate);
          }
          // Phone + YouTube: the PC prepares the preview and streams it.
          final sync = ref.read(syncServiceProvider);
          return sync.remotePreview(sync.downloadPeer!, candidate);
        }),
        child: SizedBox.square(
          dimension: _size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RemoteCover(url: candidate.coverUrl, size: _size),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(
                    alpha: state == null ? 0.25 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
              ),
              if (state?.loading ?? false)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                if (state != null && state.failure == null)
                  SizedBox.square(
                    dimension: 34,
                    child: CircularProgressIndicator(
                      value: state.fraction,
                      strokeWidth: 2.5,
                      color: accent,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                Icon(
                  state?.failure != null
                      ? Icons.error_outline_rounded
                      : playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
