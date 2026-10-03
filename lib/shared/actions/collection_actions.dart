import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/collections_providers.dart';
import '../../core/library/library_models.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/cover_art.dart';

ProviderContainer _container(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false);

Future<void> toggleLike(BuildContext context, LibraryTrack track) =>
    _container(context)
        .read(collectionsRepositoryProvider)
        .setLiked(track.id, liked: !track.liked);

/// Asks for a playlist name. Returns the trimmed name, or null if cancelled.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  String initial = '',
  required String title,
  required String action,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) =>
        _NameDialog(initial: initial, title: title, action: action),
  );
  return (name == null || name.isEmpty) ? null : name;
}

/// Owns its text controller, so the controller lives exactly as long as the
/// dialog — including its closing animation.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.initial,
    required this.title,
    required this.action,
  });

  final String initial;
  final String title;
  final String action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: l10n.playlistName,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

/// Creates a playlist after asking for its name.
Future<({String id, String name})?> createPlaylistInteractive(
  BuildContext context,
) async {
  final l10n = AppLocalizations.of(context);
  final name = await showPlaylistNameDialog(
    context,
    title: l10n.newPlaylist,
    action: l10n.create,
  );
  if (name == null || !context.mounted) return null;
  final id = await _container(context)
      .read(collectionsRepositoryProvider)
      .createPlaylist(name);
  return (id: id, name: name);
}

/// Bottom sheet: pick a playlist (or create one) and add [tracks] to it.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  final l10n = AppLocalizations.of(context);
  final container = _container(context);
  final messenger = ScaffoldMessenger.of(context);

  final picked = await showModalBottomSheet<({String id, String name})>(
    context: context,
    backgroundColor: AppColors.overlay,
    showDragHandle: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final playlists = ref.watch(playlistsProvider).value ?? const [];
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.addToPlaylist,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(l10n.newPlaylist),
              onTap: () async {
                final created = await createPlaylistInteractive(context);
                if (created == null || !sheetContext.mounted) return;
                Navigator.pop(sheetContext, created);
              },
            ),
            for (final p in playlists)
              ListTile(
                leading: CoverArt(path: p.coverPath, size: 40),
                title: Text(p.name),
                subtitle: Text(l10n.trackCount(p.trackCount)),
                onTap: () =>
                    Navigator.pop(sheetContext, (id: p.id, name: p.name)),
              ),
          ],
        );
      },
    ),
  );
  if (picked == null) return;

  final added = await container
      .read(collectionsRepositoryProvider)
      .addToPlaylist(picked.id, [for (final t in tracks) t.id]);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        added == 0
            ? l10n.alreadyInPlaylist(picked.name)
            : l10n.addedToPlaylist(picked.name),
      ),
    ),
  );
}
