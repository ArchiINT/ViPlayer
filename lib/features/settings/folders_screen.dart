import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/media_store.dart';
import '../../core/platform/app_directories.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/glass_panel.dart';
import '../../shared/widgets/section_header.dart';

/// Where the library comes from: picked folders, the download folder (always
/// on) and, on Android, all device music via MediaStore.
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  Future<void> _addFolder(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.foldersAdd,
    );
    if (path == null) return;

    final added = await ref.read(libraryRepositoryProvider).addFolder(path);
    if (!added) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.foldersAlreadyAdded)));
      return;
    }
    await ref.read(scanControllerProvider.notifier).rescan();
  }

  Future<void> _removeFolder(
    BuildContext context,
    WidgetRef ref,
    LibraryFolderRow folder,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.foldersRemoveConfirm(folder.path)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.foldersRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(libraryRepositoryProvider).removeFolder(folder.id);
  }

  Future<void> _toggleDeviceMusic(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final denied = AppLocalizations.of(context).foldersPermissionDenied;
    if (enabled && !await const MediaStore().ensurePermission()) {
      messenger.showSnackBar(SnackBar(content: Text(denied)));
      return;
    }
    await ref.read(settingsProvider.notifier).setScanDeviceMusic(enabled);
    await ref.read(scanControllerProvider.notifier).rescan();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final folders = ref.watch(libraryFoldersProvider).value ?? const [];
    final settings = ref.watch(settingsProvider);
    final scan = ref.watch(scanControllerProvider);
    final downloads = ref.watch(appDirectoriesProvider).downloads;
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.textSecondary,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsMusicFolders)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addFolder(context, ref),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(l10n.foldersAdd),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          GlassGroup(
            children: [
              if (MediaStore.isSupported)
                SwitchListTile(
                  secondary: const Icon(Icons.smartphone_rounded),
                  title: Text(l10n.foldersDeviceMusic),
                  subtitle: Text(l10n.foldersDeviceMusicSubtitle),
                  value: settings.scanDeviceMusic,
                  onChanged: (v) => _toggleDeviceMusic(context, ref, v),
                ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(l10n.settingsDownloadFolder),
                subtitle: Text(downloads, style: mono),
                trailing: Text(
                  l10n.foldersAlwaysIncluded,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          SectionHeader(l10n.foldersPicked),
          GlassGroup(
            children: [
              if (folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.foldersEmpty,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              for (final folder in folders)
                ListTile(
                  leading: Switch(
                    value: folder.enabled,
                    onChanged: (enabled) async {
                      await ref
                          .read(libraryRepositoryProvider)
                          .setFolderEnabled(folder.id, enabled: enabled);
                      await ref.read(scanControllerProvider.notifier).rescan();
                    },
                  ),
                  title: Text(folder.path, style: mono.copyWith(fontSize: 13)),
                  trailing: IconButton(
                    tooltip: l10n.foldersRemove,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _removeFolder(context, ref, folder),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          GlassGroup(
            children: [
              ListTile(
                leading: scan.running
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                title: Text(l10n.libraryRescan),
                subtitle: switch (scan) {
                  ScanState(error: != null) => Text(
                    l10n.scanFailed,
                    style: const TextStyle(color: AppColors.error),
                  ),
                  ScanState(:final last?) => Text(
                    l10n.scanLastResult(last.totalFiles),
                    style: mono,
                  ),
                  _ => null,
                },
                enabled: !scan.running,
                onTap: () => ref.read(scanControllerProvider.notifier).rescan(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
