import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/download_models.dart';
import '../../../core/download/download_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../download_texts.dart';
import 'remote_cover.dart';

/// "By link": paste a link, see what it is, download it (or pick tracks of
/// an album / playlist).
class LinkPanel extends ConsumerStatefulWidget {
  const LinkPanel({super.key});

  @override
  ConsumerState<LinkPanel> createState() => _LinkPanelState();
}

class _LinkPanelState extends ConsumerState<LinkPanel> {
  final _controller = TextEditingController();
  bool _loading = false;
  ResolvedLink? _result;
  DownloadFailure? _error;
  Set<DownloadCandidate> _selected = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    await _find();
  }

  Future<void> _find() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref.read(downloadServiceProvider).resolve(text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _selected = result.items.toSet();
      });
    } on DownloadException catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _download(List<DownloadCandidate> items) {
    ref.read(downloadQueueProvider).enqueue(items);
    setState(() {
      _result = null;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final service = ref.watch(downloadServiceProvider);
    final result = _result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onSubmitted: (_) => _find(),
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: l10n.downloadsLinkHint,
            prefixIcon: const Icon(Icons.link_rounded),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.paste,
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
                IconButton(
                  tooltip: l10n.find,
                  onPressed: _find,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: switch ((_loading, _error, result)) {
              (true, _, _) => const LinearProgressIndicator(),
              (_, final error?, _) => _Message(text: l10n.failure(error)),
              (_, _, final r?) when !service.supports(r.service) => _Message(
                text: l10n.failNotOnThisDevice,
              ),
              (_, _, final r?) when !r.isCollection => _SingleResult(
                item: r.items.single,
                onDownload: () => _download(r.items),
              ),
              (_, _, final r?) => _CollectionResult(
                result: r,
                selected: _selected,
                onToggle: (c) => setState(
                  () => _selected.contains(c)
                      ? _selected.remove(c)
                      : _selected.add(c),
                ),
                onDownload: () => _download([
                  for (final c in r.items)
                    if (_selected.contains(c)) c,
                ]),
              ),
              _ => const SizedBox(width: double.infinity),
            },
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    ),
  );
}

class _SingleResult extends StatelessWidget {
  const _SingleResult({required this.item, required this.onDownload});

  final DownloadCandidate item;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          RemoteCover(url: item.coverUrl, size: 72),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item.artist,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${serviceName(item.service)} · '
                  '${formatTrackDuration(item.durationMs)}',
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded),
            label: Text(l10n.download),
          ),
        ],
      ),
    );
  }
}

class _CollectionResult extends StatelessWidget {
  const _CollectionResult({
    required this.result,
    required this.selected,
    required this.onToggle,
    required this.onDownload,
  });

  final ResolvedLink result;
  final Set<DownloadCandidate> selected;
  final void Function(DownloadCandidate) onToggle;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: RemoteCover(
              url: result.collectionCoverUrl ?? result.items.first.coverUrl,
              size: 56,
            ),
            title: Text(
              result.collectionTitle!,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${serviceName(result.service)} · '
              '${l10n.trackCount(result.items.length)}',
            ),
            trailing: FilledButton.icon(
              onPressed: selected.isEmpty ? null : onDownload,
              icon: const Icon(Icons.download_rounded),
              label: Text(l10n.downloadAll(selected.length)),
            ),
          ),
          const Divider(),
          // Bounded so a 500-track playlist does not build 500 rows at once.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: result.items.length,
              itemExtent: 52,
              itemBuilder: (context, i) {
                final c = result.items[i];
                return CheckboxListTile(
                  dense: true,
                  value: selected.contains(c),
                  onChanged: (_) => onToggle(c),
                  title: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    c.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: Text(
                    formatTrackDuration(c.durationMs),
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
