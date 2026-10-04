import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_models.dart';
import '../../core/library/library_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/actions/playback.dart';
import '../../shared/widgets/empty_state.dart';
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
                : _Results(tracks: result),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.tracks});

  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      itemExtent: TrackTile.extent,
      itemCount: tracks.length,
      itemBuilder: (context, i) => TrackTile(
        track: tracks[i],
        onTap: () => playTrack(context, tracks[i], queue: tracks),
      ),
    );
  }
}
