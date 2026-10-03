import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/player_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/glass_panel.dart';

/// Opens the queue as a bottom sheet (phones).
Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.overlay,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
  ),
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, controller) =>
        QueueView(scrollController: controller, framed: false),
  ),
);

/// The play queue: tap to jump, drag to reorder, swipe to remove.
/// Starts scrolled to the current track.
class QueueView extends ConsumerStatefulWidget {
  const QueueView({super.key, this.scrollController, this.framed = true});

  final ScrollController? scrollController;

  /// Draws its own glass panel (side-by-side layout) or not (sheet).
  final bool framed;

  @override
  ConsumerState<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends ConsumerState<QueueView> {
  static const _rowHeight = 60.0;
  late final ScrollController _controller =
      widget.scrollController ??
      ScrollController(
        initialScrollOffset:
            ref.read(playerSnapshotProvider).index.clamp(0, 1 << 20) *
            _rowHeight,
      );

  @override
  void dispose() {
    if (widget.scrollController == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(playerSnapshotProvider);
    final player = ref.read(playerServiceProvider);
    final accent = Theme.of(context).colorScheme.primary;
    final queue = snapshot.queue;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        l10n.queue,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );

    final list = queue.isEmpty
        ? Center(
            child: Text(
              l10n.queueEmpty,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          )
        : ReorderableListView.builder(
            scrollController: _controller,
            buildDefaultDragHandles: false,
            itemExtent: _rowHeight,
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: queue.length,
            onReorderItem: player.reorder,
            itemBuilder: (context, i) {
              final track = queue[i];
              final isCurrent = i == snapshot.index;
              return Dismissible(
                // Same song may be queued twice: key by position too.
                key: ValueKey('${track.id}#$i'),
                direction: isCurrent
                    ? DismissDirection.none
                    : DismissDirection.endToStart,
                onDismissed: (_) => player.removeAt(i),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: AppColors.error.withValues(alpha: 0.2),
                  child: Tooltip(
                    message: l10n.removeFromQueue,
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
                child: ListTile(
                  onTap: () => player.jumpTo(i),
                  selected: isCurrent,
                  selectedTileColor: AppColors.glassStrong,
                  leading: CoverArt(path: track.coverPath, size: 40),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? accent : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(
                      Icons.drag_handle_rounded,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              );
            },
          );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Expanded(child: list),
      ],
    );
    return widget.framed ? GlassPanel(child: content) : content;
  }
}
