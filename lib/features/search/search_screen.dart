import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_models.dart';
import '../../core/library/library_providers.dart';
import '../../core/router/app_router.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/actions/playback.dart';
import '../../shared/widgets/album_card.dart';
import '../../shared/widgets/artist_tile.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/track_tile.dart';

/// Searches the local library as you type. Online search (downloads by name)
/// lives in the Downloads tab.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  /// Short pause after typing so huge libraries are not re-filtered on
  /// every keystroke.
  static const _debounce = Duration(milliseconds: 120);

  final _controller = TextEditingController();
  Timer? _timer;
  String _query = '';

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => setState(() => _query = value.trim()));
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final index = ref.watch(libraryIndexProvider).value ?? LibraryIndex.empty;
    final result = index.search(_query);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSearch)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _clear,
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          Expanded(
            child: _query.isEmpty
                ? EmptyState(
                    icon: Icons.manage_search,
                    title: l10n.navSearch,
                    message: l10n.searchEmptyBody,
                  )
                : result.isEmpty
                ? EmptyState(
                    icon: Icons.search_off,
                    title: l10n.searchNoResults(_query),
                    message: '',
                  )
                : _Results(result: result),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.result});

  /// Albums/artists are a quick jump, not the main result — keep them short.
  static const _maxGroupItems = 8;

  final LibrarySearchResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final artists = result.artists.take(_maxGroupItems).toList();
    final albums = result.albums.take(_maxGroupItems).toList();

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (artists.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader(l10n.libraryArtists)),
          SliverFixedExtentList(
            itemExtent: ArtistTile.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) => ArtistTile(
                artist: artists[i],
                onTap: () => openArtist(context, artists[i].name),
              ),
              childCount: artists.length,
            ),
          ),
        ],
        if (albums.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader(l10n.libraryAlbums)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 210,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: albums.length,
                itemBuilder: (context, i) => SizedBox(
                  width: 160,
                  child: AlbumCard(
                    album: albums[i],
                    onTap: () => openAlbum(context, albums[i].key),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (result.tracks.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader(l10n.libraryTracks)),
          SliverFixedExtentList(
            itemExtent: TrackTile.extent,
            delegate: SliverChildBuilderDelegate(
              (context, i) => TrackTile(
                track: result.tracks[i],
                onTap: () =>
                    playTrack(context, result.tracks[i], queue: result.tracks),
              ),
              childCount: result.tracks.length,
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}
