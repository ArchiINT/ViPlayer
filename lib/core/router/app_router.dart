import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/downloads/downloads_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/player/mini_player.dart';
import '../../features/player/now_playing_screen.dart';
import '../../features/playlists/playlist_screen.dart';
import '../../features/playlists/recent_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/folders_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/sync/pairing_code_dialog.dart';
import '../../features/sync/sync_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../theme/app_theme.dart';

/// Top-level destinations, in navigation order.
abstract final class AppRoutes {
  static const library = '/library';
  static const search = '/search';
  static const downloads = '/downloads';
  static const settings = '/settings';
  static const folders = '/settings/folders';
  static const sync = '/settings/sync';

  /// Inside the library tab (Playlists sub-tab).
  static const recent = '/library/recent';
  static String playlist(String id) => '/library/p/$id';

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
        builder: (context, state, shell) => PairingCodeListener(
          child: AppShell(shell: shell, miniPlayer: const MiniPlayer()),
        ),
        branches: [
          _branch(
            AppRoutes.library,
            const LibraryScreen(),
            routes: [
              GoRoute(
                path: 'recent',
                builder: (context, state) => const RecentScreen(),
              ),
              GoRoute(
                path: 'p/:id',
                builder: (context, state) =>
                    PlaylistScreen(playlistId: state.pathParameters['id']!),
              ),
            ],
          ),
          _branch(AppRoutes.search, const SearchScreen()),
          _branch(AppRoutes.downloads, const DownloadsScreen()),
          _branch(
            AppRoutes.settings,
            const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'folders',
                builder: (context, state) => const FoldersScreen(),
              ),
              GoRoute(
                path: 'sync',
                builder: (context, state) => const SyncScreen(),
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
