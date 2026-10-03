import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/download/download_models.dart';
import '../../core/download/download_providers.dart';
import '../../core/library/library_providers.dart';
import '../../core/platform/app_directories.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/glass_panel.dart';
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
    final folderCount = ref.watch(libraryFoldersProvider).value?.length ?? 0;
    const pathStyle = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.textSecondary,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          SectionHeader(l10n.settingsAppearance),
          GlassGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.translate_rounded),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final accent in Accent.values)
                      _AccentSwatch(
                        accent: accent,
                        label: _accentLabel(l10n, accent),
                        selected: accent == settings.accent,
                        onTap: () => controller.setAccent(accent),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SectionHeader(l10n.settingsLibrary),
          GlassGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(l10n.settingsMusicFolders),
                subtitle: folderCount == 0
                    ? null
                    : Text('$folderCount', style: pathStyle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.go(AppRoutes.folders),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(l10n.settingsDownloadFolder),
                subtitle: Text(
                  ref.watch(appDirectoriesProvider).downloads,
                  style: pathStyle,
                ),
              ),
            ],
          ),
          SectionHeader(l10n.settingsDownloads),
          const _DownloadSettings(),
          SectionHeader(l10n.settingsAbout),
          GlassGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(l10n.appTitle),
                subtitle: Text(
                  l10n.settingsVersion(version ?? '…'),
                  style: pathStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _accentLabel(AppLocalizations l10n, Accent accent) =>
      switch (accent) {
        Accent.sky => l10n.accentSky,
        Accent.rose => l10n.accentRose,
        Accent.mint => l10n.accentMint,
        Accent.lavender => l10n.accentLavender,
        Accent.amber => l10n.accentAmber,
      };
}

/// Round colour dot; the selected one gets a ring and a check mark.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Accent accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.textPrimary : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.color,
            ),
            child: selected
                ? const Icon(
                    Icons.check_rounded,
                    color: AppColors.base,
                    size: 18,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Download format and, on the desktop, the yt-dlp engine.
class _DownloadSettings extends ConsumerStatefulWidget {
  const _DownloadSettings();

  @override
  ConsumerState<_DownloadSettings> createState() => _DownloadSettingsState();
}

class _DownloadSettingsState extends ConsumerState<_DownloadSettings> {
  bool _updating = false;

  Future<void> _updateYtDlp() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updating = true);
    try {
      final version = await ref
          .read(ytDlpProvider)!
          .update(ref.read(httpClientProvider));
      ref.invalidate(ytDlpVersionProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.ytdlpUpdated(version ?? '?'))),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ytdlpUpdateFailed)));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = ref.watch(availableFormatsProvider);
    final current = ref.watch(settingsProvider).downloadFormat;
    final hasYtDlp = ref.watch(ytDlpProvider) != null;
    final version = ref.watch(ytDlpVersionProvider);

    String label(DownloadFormat f) => switch (f) {
      DownloadFormat.m4a => l10n.formatM4a,
      DownloadFormat.opus => l10n.formatOpus,
      DownloadFormat.mp3 => l10n.formatMp3,
    };

    return GlassGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.audio_file_outlined),
          title: Text(l10n.settingsFormat),
          subtitle: Text(
            label(formats.contains(current) ? current : formats.first),
          ),
          trailing: formats.length < 2
              ? null
              : PopupMenuButton<DownloadFormat>(
                  icon: const Icon(Icons.expand_more_rounded),
                  initialValue: current,
                  onSelected: ref
                      .read(settingsProvider.notifier)
                      .setDownloadFormat,
                  itemBuilder: (context) => [
                    for (final f in formats)
                      CheckedPopupMenuItem(
                        value: f,
                        checked: f == current,
                        child: Text(label(f)),
                      ),
                  ],
                ),
        ),
        if (hasYtDlp)
          ListTile(
            leading: const Icon(Icons.terminal_rounded),
            title: Text(switch (version) {
              AsyncData(value: final v?) => l10n.ytdlpVersion(v),
              AsyncData() => l10n.ytdlpMissing,
              _ => 'yt-dlp',
            }),
            trailing: _updating
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : OutlinedButton(
                    onPressed: _updateYtDlp,
                    child: Text(
                      version.value == null
                          ? l10n.ytdlpInstall
                          : l10n.ytdlpUpdate,
                    ),
                  ),
          ),
      ],
    );
  }
}
