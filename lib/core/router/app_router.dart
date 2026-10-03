import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/downloads/downloads_screen.dart';
import '../../features/library/album_screen.dart';
import '../../features/library/artist_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/player/mini_player.dart';
import '../../features/player/now_playing_screen.dart';
import '../../features/playlists/playlists_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/folders_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../theme/app_theme.dart';

/// Top-level destinations, in navigation order.
abstract final class AppRoutes {
  static const library = '/library';
  static const search = '/search';
  static const playlists = '/playlists';
  static const downloads = '/downloads';
  static const settings = '/settings';
  static const folders = '/settings/folders';

  /// Full-screen player, above the tabs.
  static const player = '/player';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.library,
    routes: [
      GoRoute(
        path: AppRoutes.player,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          // Covers the whole screen with its own backdrop, so the tabs
          // underneath need not be painted once the transition ends.
          opaque: true,
          transitionDuration: AppMotion.normal,
          reverseTransitionDuration: AppMotion.normal,
          child: const NowPlayingScreen(),
          // Slides up from the mini player.
          transitionsBuilder: (context, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: AppMotion.curve,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        ),
      ),
      // Each tab keeps its own navigation stack and scroll position.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppShell(shell: shell, miniPlayer: const MiniPlayer()),
        branches: [
          _branch(
            AppRoutes.library,
            const LibraryScreen(),
            routes: _detailRoutes(),
          ),
          _branch(
            AppRoutes.search,
            const SearchScreen(),
            routes: _detailRoutes(),
          ),
          _branch(AppRoutes.playlists, const PlaylistsScreen()),
          _branch(AppRoutes.downloads, const DownloadsScreen()),
          _branch(
            AppRoutes.settings,
            const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'folders',
                builder: (context, state) => const FoldersScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(
  String path,
  Widget screen, {
  List<RouteBase> routes = const [],
}) => StatefulShellBranch(
  routes: [
    GoRoute(path: path, builder: (context, state) => screen, routes: routes),
  ],
);

/// Album and artist pages, available inside every tab that lists music so
/// opening one never jumps to another tab.
List<RouteBase> _detailRoutes() => [
  GoRoute(
    path: 'album/:key',
    builder: (context, state) =>
        AlbumScreen(albumKey: state.pathParameters['key']!),
  ),
  GoRoute(
    path: 'artist/:name',
    builder: (context, state) =>
        ArtistScreen(artistName: state.pathParameters['name']!),
  ),
];

/// Opens an album page within the current tab.
void openAlbum(BuildContext context, String albumKey) =>
    context.push('${_tabRoot(context)}/album/${Uri.encodeComponent(albumKey)}');

/// Opens an artist page within the current tab.
void openArtist(BuildContext context, String name) =>
    context.push('${_tabRoot(context)}/artist/${Uri.encodeComponent(name)}');

String _tabRoot(BuildContext context) =>
    '/${GoRouterState.of(context).uri.pathSegments.first}';
