import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/library_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/actions/playback.dart';
import '../../shared/utils/format.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/track_tile.dart';
import 'tabs/liked_tab.dart';
import 'tabs/long_tab.dart';
import 'tabs/playlists_tab.dart';
import 'widgets/scan_status_bar.dart';

final trackSortProvider = NotifierProvider<TrackSortController, TrackSort>(
  TrackSortController.new,
);

class TrackSortController extends Notifier<TrackSort> {
  @override
  TrackSort build() => TrackSort.title;

  void set(TrackSort sort) => state = sort;
}

/// Sorted once per library change or sort change, not on every rebuild.
final _sortedTracksProvider = Provider<List<LibraryTrack>>(
  (ref) => LibraryIndex.sortTracks(
    ref.watch(musicTracksProvider),
    ref.watch(trackSortProvider),
  ),
);

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final index = ref.watch(libraryIndexProvider);
    final scanning = ref.watch(scanControllerProvider.select((s) => s.running));

    final showLong = ref.watch(
      settingsProvider.select((s) => s.longAudioMinutes > 0),
    );

    return DefaultTabController(
      // Rebuilt when the Books & podcasts tab is switched on or off.
      key: ValueKey(showLong),
      length: showLong ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navLibrary),
          actions: [
            const _SortButton(),
            IconButton(
              tooltip: l10n.libraryRescan,
              onPressed: scanning
                  ? null
                  : () => ref.read(scanControllerProvider.notifier).rescan(),
              icon: const Icon(Icons.sync),
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            tabs: [
              Tab(text: l10n.libraryTracks),
              Tab(text: l10n.playlistsLiked),
              Tab(text: l10n.navPlaylists),
              if (showLong) Tab(text: l10n.tabLong),
            ],
          ),
        ),
        // The scan indicator floats over the content instead of pushing it
        // down, so progress updates never re-layout the lists.
        body: Stack(
          children: [
            Positioned.fill(
              child: switch (index) {
                AsyncData(:final value) when value.isEmpty =>
                  scanning ? const SizedBox.shrink() : const _EmptyLibrary(),
                AsyncData(:final value) => TabBarView(
                  children: [
                    _KeepAlive(child: _TracksTab(index: value)),
                    const _KeepAlive(child: LikedTab()),
                    const _KeepAlive(child: PlaylistsTab()),
                    if (showLong) const _KeepAlive(child: LongTab()),
                  ],
                ),
                AsyncError() => Center(child: Text(l10n.libraryLoadFailed)),
                _ => const SizedBox.shrink(),
              },
            ),
            const Positioned(left: 0, right: 0, top: 0, child: ScanStatusBar()),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.library_music_outlined,
      title: l10n.libraryEmptyTitle,
      message: l10n.libraryEmptyBody,
      action: OutlinedButton.icon(
        onPressed: () => context.go(AppRoutes.folders),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(l10n.settingsMusicFolders),
      ),
    );
  }
}

class _SortButton extends ConsumerWidget {
  const _SortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(trackSortProvider);
    final labels = {
      TrackSort.title: l10n.sortTitle,
      TrackSort.artist: l10n.sortArtist,
      TrackSort.album: l10n.sortAlbum,
      TrackSort.recentlyAdded: l10n.sortRecentlyAdded,
    };
    return PopupMenuButton<TrackSort>(
      tooltip: l10n.sortBy,
      icon: const Icon(Icons.sort),
      initialValue: current,
      onSelected: ref.read(trackSortProvider.notifier).set,
      itemBuilder: (context) => [
        for (final MapEntry(:key, :value) in labels.entries)
          CheckedPopupMenuItem(
            value: key,
            checked: key == current,
            child: Text(value),
          ),
      ],
    );
  }
}

class _TracksTab extends ConsumerWidget {
  const _TracksTab({required this.index});

  final LibraryIndex index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracks = ref.watch(_sortedTracksProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              '${l10n.trackCount(tracks.length)} · '
              '${formatTotalDuration(l10n, tracks.fold(0, (sum, t) => sum + t.durationMs))}',
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        SliverFixedExtentList(
          itemExtent: TrackTile.extent,
          delegate: SliverChildBuilderDelegate(
            (context, i) => TrackTile(
              track: tracks[i],
              onTap: () => playTrack(context, tracks[i], queue: tracks),
            ),
            childCount: tracks.length,
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

/// Keeps a tab's widgets (and scroll position, decoded images) alive while
/// another tab is shown, so swiping back does not rebuild it mid-animation.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
