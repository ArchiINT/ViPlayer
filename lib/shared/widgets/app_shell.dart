import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/library_providers.dart';
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
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

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

  @override
  Widget build(BuildContext context) {
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
            Expanded(child: shell),
          ],
        ),
      );
    } else {
      content = Scaffold(
        body: shell,
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: SafeArea(
            top: false,
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
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        AmbientBackground(coverPath: ref.watch(ambientCoverProvider)),
        content,
      ],
    );
  }
}
