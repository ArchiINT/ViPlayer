import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/downloads/downloads_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/playlists/playlists_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../shared/widgets/app_shell.dart';

/// Top-level destinations, in navigation order.
abstract final class AppRoutes {
  static const library = '/library';
  static const search = '/search';
  static const playlists = '/playlists';
  static const downloads = '/downloads';
  static const settings = '/settings';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.library,
    routes: [
      // Each tab keeps its own navigation stack and scroll position.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          _branch(AppRoutes.library, const LibraryScreen()),
          _branch(AppRoutes.search, const SearchScreen()),
          _branch(AppRoutes.playlists, const PlaylistsScreen()),
          _branch(AppRoutes.downloads, const DownloadsScreen()),
          _branch(AppRoutes.settings, const SettingsScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);
