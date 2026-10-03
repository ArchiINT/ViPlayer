import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/platform/app_paths.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/section_header.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final version = ref.watch(_packageInfoProvider).value?.version;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader(l10n.settingsAppearance),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.settingsLanguage),
            trailing: SegmentedButton<AppLanguage>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: AppLanguage.en, label: Text('EN')),
                ButtonSegment(value: AppLanguage.ru, label: Text('RU')),
              ],
              selected: {settings.language},
              onSelectionChanged: (s) => controller.setLanguage(s.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.settingsAccent),
            subtitle: Text(_accentLabel(l10n, settings.accent)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final accent in NeonAccent.values)
                  _AccentSwatch(
                    accent: accent,
                    label: _accentLabel(l10n, accent),
                    selected: accent == settings.accent,
                    onTap: () => controller.setAccent(accent),
                  ),
              ],
            ),
          ),
          SectionHeader(l10n.settingsLibrary),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.settingsMusicFolders),
            subtitle: Text(l10n.comingSoon),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.settingsDownloadFolder),
            subtitle: Text(
              AppPaths.downloadDirectory(),
              style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
            ),
          ),
          SectionHeader(l10n.settingsAbout),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.appTitle),
            subtitle: Text(
              l10n.settingsVersion(version ?? '…'),
              style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  static String _accentLabel(AppLocalizations l10n, NeonAccent accent) =>
      switch (accent) {
        NeonAccent.cyan => l10n.accentCyan,
        NeonAccent.magenta => l10n.accentMagenta,
        NeonAccent.acid => l10n.accentAcid,
        NeonAccent.violet => l10n.accentViolet,
      };
}

/// Chamfered color tile; the selected one glows.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final NeonAccent accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = accent.color;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          width: 44,
          height: 44,
          decoration: ShapeDecoration(
            color: selected ? color : color.withValues(alpha: 0.18),
            shape: BeveledRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              side: BorderSide(color: color, width: selected ? 2 : 1),
            ),
            shadows: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.55),
                      blurRadius: 16,
                    ),
                  ]
                : const [],
          ),
          child: selected
              ? const Icon(Icons.check, color: AppColors.background, size: 20)
              : null,
        ),
      ),
    );
  }
}
