import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/library_providers.dart';
import '../../core/player/player_providers.dart';
import '../../core/sync/sync_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import 'ambient_background.dart';
import 'app_logo.dart';
import 'glass_panel.dart';

/// Breakpoint between the phone layout (bottom bar) and the wide layout
/// (side rail).
const _wideLayoutMinWidth = 720.0;

/// Adaptive frame around the tab screens: bottom navigation bar on phones,
/// navigation rail on desktop / wide windows.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell, required this.miniPlayer});

  final StatefulNavigationShell shell;

  /// Docked player (provided by the router, so shared/ does not depend on
  /// the player feature).
  final Widget miniPlayer;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    // Refresh the library in the background once the UI is up; the scan is
    // incremental, so this is cheap when nothing changed.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(scanControllerProvider.notifier).rescan(),
    );
  }

  void _onSelect(int index) => shell.goBranch(
    index,
    // Tapping the active tab returns it to its root screen.
    initialLocation: index == shell.currentIndex,
  );

  /// Desktop keyboard control. Text fields consume these keys first, so
  /// typing a space in search never pauses the music.
  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final player = ref.read(playerServiceProvider);
    void seekBy(int seconds) {
      final target = player.currentPosition + Duration(seconds: seconds);
      player.seek(target < Duration.zero ? Duration.zero : target);
    }

    return {
      const SingleActivator(LogicalKeyboardKey.space): player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
          player.playOrPause,
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
          player.next,
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
          player.previous,
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(5),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(-5),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Session restore, library <-> queue sync (see playerBootstrapProvider).
    ref.watch(playerBootstrapProvider);
    ref.watch(syncBootstrapProvider);
    final l10n = AppLocalizations.of(context);
    final destinations = [
      (
        Icons.library_music_outlined,
        Icons.library_music_rounded,
        l10n.navLibrary,
      ),
      (Icons.search_rounded, Icons.search_rounded, l10n.navSearch),
      (
        Icons.queue_music_outlined,
        Icons.queue_music_rounded,
        l10n.navPlaylists,
      ),
      (Icons.download_outlined, Icons.download_rounded, l10n.navDownloads),
      (Icons.settings_outlined, Icons.settings_rounded, l10n.navSettings),
    ];

    final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutMinWidth;

    final Widget content;
    if (isWide) {
      content = Scaffold(
        body: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: GlassPanel(
                strong: true,
                child: NavigationRail(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: _onSelect,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 76,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: AppLogo(size: 15),
                  ),
                  destinations: [
                    for (final (icon, selectedIcon, label) in destinations)
                      NavigationRailDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selectedIcon),
                        label: Text(label),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: shell),
                  widget.miniPlayer,
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      content = Scaffold(
        body: shell,
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.miniPlayer,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: GlassPanel(
                    strong: true,
                    radius: 28,
                    child: NavigationBar(
                      selectedIndex: shell.currentIndex,
                      onDestinationSelected: _onSelect,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.onlyShowSelected,
                      destinations: [
                        for (final (icon, selectedIcon, label) in destinations)
                          NavigationDestination(
                            icon: Icon(icon),
                            selectedIcon: Icon(selectedIcon),
                            label: label,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The whole app is tinted by the cover of what is playing.
            AmbientBackground(
              coverPath: ref.watch(
                currentTrackProvider.select((t) => t?.coverPath),
              ),
            ),
            content,
          ],
        ),
      ),
    );
  }
}
