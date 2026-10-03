import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import 'app_logo.dart';

/// Breakpoint between the phone layout (bottom bar) and the wide layout
/// (side rail).
const _wideLayoutMinWidth = 720.0;

/// Adaptive frame around the tab screens: bottom navigation bar on phones,
/// navigation rail on desktop / wide windows.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  void _onSelect(int index) => shell.goBranch(
    index,
    // Tapping the active tab returns it to its root screen.
    initialLocation: index == shell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destinations = [
      (Icons.library_music_outlined, Icons.library_music, l10n.navLibrary),
      (Icons.search, Icons.search, l10n.navSearch),
      (Icons.queue_music_outlined, Icons.queue_music, l10n.navPlaylists),
      (Icons.download_outlined, Icons.download, l10n.navDownloads),
      (Icons.settings_outlined, Icons.settings, l10n.navSettings),
    ];

    final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutMinWidth;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _onSelect,
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
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
            const VerticalDivider(width: 1, color: AppColors.outline),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _onSelect,
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
    );
  }
}
