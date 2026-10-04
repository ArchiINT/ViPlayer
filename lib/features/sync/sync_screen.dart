import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/sync/discovery.dart';
import '../../core/sync/peer_store.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/utils/sync_texts.dart';
import '../../shared/widgets/glass_panel.dart';
import '../../shared/widgets/section_header.dart';

/// This device's LAN addresses, for connecting by hand.
final _localAddressesProvider = FutureProvider<List<String>>((ref) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  return [
    for (final i in interfaces)
      for (final a in i.addresses)
        if (!a.isLoopback) a.address,
  ];
});

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final service = ref.watch(syncServiceProvider);
    final s = ref.watch(syncSnapshotProvider);
    final unpairedNearby = [
      for (final d in s.nearby.values)
        if (!s.paired.containsKey(d.id)) d,
    ];
    final addresses = ref.watch(_localAddressesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
        children: [
          if (!s.running)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                l10n.syncNotRunning,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          SectionHeader(l10n.syncThisDevice),
          GlassGroup(
            children: [
              ListTile(
                leading: Icon(_icon(thisDeviceKind)),
                title: Text(s.deviceName),
                subtitle: Text(
                  [
                    l10n.syncVisibleAs(s.deviceName),
                    if (service.port != null && addresses.isNotEmpty)
                      l10n.syncThisAddress(
                        '${addresses.first}:${service.port}',
                      ),
                  ].join('\n'),
                ),
                trailing: const Icon(Icons.edit_rounded),
                onTap: () => _rename(context, ref),
              ),
              if (thisDeviceKind == DeviceKind.phone) const _CopyAllSwitch(),
            ],
          ),
          SectionHeader(l10n.syncPaired),
          if (s.paired.isEmpty)
            _Hint(l10n.syncNoPaired)
          else
            GlassGroup(
              children: [
                for (final peer in s.paired.values)
                  _PairedTile(
                    peer: peer,
                    online: s.nearby.containsKey(peer.id),
                    state: s.states[peer.id],
                  ),
              ],
            ),
          SectionHeader(l10n.syncNearby),
          if (unpairedNearby.isEmpty)
            _Hint(l10n.syncNoNearby)
          else
            GlassGroup(
              children: [
                for (final d in unpairedNearby)
                  ListTile(
                    leading: Icon(_icon(d.kind)),
                    title: Text(d.name),
                    subtitle: Text(
                      d.host,
                      style: const TextStyle(fontFamily: AppFonts.mono),
                    ),
                    trailing: FilledButton(
                      onPressed: () => _pair(context, ref, d),
                      child: Text(l10n.syncPair),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _connectByAddress(context, ref),
              icon: const Icon(Icons.lan_outlined),
              label: Text(l10n.syncConnectByIp),
            ),
          ),
          const SizedBox(height: 8),
          _Hint(l10n.syncSecurityNote),
        ],
      ),
    );
  }

  static IconData _icon(DeviceKind kind) => kind == DeviceKind.phone
      ? Icons.smartphone_rounded
      : Icons.computer_rounded;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(syncServiceProvider);
    final name = await _askText(
      context,
      title: l10n.syncRename,
      initial: service.deviceName,
      action: l10n.save,
    );
    if (name == null || name.isEmpty) return;
    await service.rename(name);
  }

  Future<void> _pair(
    BuildContext context,
    WidgetRef ref,
    NearbyDevice device,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(syncServiceProvider);
    try {
      await service.requestPairing(device.id);
    } on SyncException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.syncFailure(e.reason))),
      );
      return;
    }
    if (!context.mounted) return;
    final code = await _askText(
      context,
      title: l10n.syncEnterCode(device.name),
      action: l10n.syncPair,
      digits: true,
    );
    if (code == null || code.isEmpty) return;
    try {
      await service.confirmPairing(device.id, code);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.syncPairedWith(device.name))),
      );
    } on SyncException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.syncWrongCode)));
    }
  }

  Future<void> _connectByAddress(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final text = await _askText(
      context,
      title: l10n.syncConnectByIp,
      hint: l10n.syncConnectHint,
      action: l10n.connect,
    );
    if (text == null || text.trim().isEmpty) return;
    final address = parseDeviceAddress(text);
    if (address == null) {
      _notify(messenger, l10n.syncBadAddress);
      return;
    }
    final (host, port) = address;
    final shown = '$host:$port';
    _notify(messenger, l10n.syncConnecting(shown));
    final service = ref.read(syncServiceProvider);
    try {
      final device = await service.connect(host, port);
      final paired = service.snapshot.value.paired.containsKey(device.id);
      _notify(
        messenger,
        paired ? l10n.syncConnected(device.name) : l10n.syncFound(device.name),
      );
      if (paired) unawaited(service.syncWith(device.id).catchError((_) => 0));
    } on SyncException catch (e) {
      _notify(
        messenger,
        e.reason == SyncFailure.unreachable
            ? l10n.syncErrNoAnswer(shown)
            : l10n.syncFailure(e.reason),
      );
    }
  }
}

/// Replaces whatever notice is showing (so "Connecting…" does not linger).
void _notify(ScaffoldMessengerState messenger, String text) => messenger
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// "192.168.1.20" or "192.168.1.20:48126" → host and port; null if invalid.
@visibleForTesting
(String, int)? parseDeviceAddress(String text) {
  final match = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?::(\d{1,5}))?$',
  ).firstMatch(text.trim());
  if (match == null) return null;
  final octets = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
  if (octets.any((o) => o > 255)) return null;
  final port = match.group(5) == null
      ? SyncService.defaultHttpPort
      : int.parse(match.group(5)!);
  if (port < 1 || port > 65535) return null;
  return (octets.join('.'), port);
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
    ),
  );
}

class _PairedTile extends ConsumerWidget {
  const _PairedTile({required this.peer, required this.online, this.state});

  final PairedPeer peer;
  final bool online;
  final PeerSyncState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(syncServiceProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final st = state;

    final status = switch (st) {
      PeerSyncState(phase: PeerPhase.syncing, filesTotal: > 0) =>
        l10n.syncFiles(st.filesDone, st.filesTotal),
      PeerSyncState(phase: PeerPhase.syncing) => l10n.syncInProgress,
      PeerSyncState(phase: PeerPhase.error, :final failure?) =>
        l10n.syncFailure(failure),
      _ when peer.lastSync != null => l10n.syncLast(
        DateFormat.MMMd(locale).add_Hm().format(peer.lastSync!),
      ),
      _ => l10n.syncNever,
    };

    return ListTile(
      leading: Icon(
        peer.kind == DeviceKind.phone
            ? Icons.smartphone_rounded
            : Icons.computer_rounded,
        color: online
            ? Theme.of(context).colorScheme.primary
            : AppColors.textTertiary,
      ),
      title: Text(peer.name),
      subtitle: Text(
        '${online ? l10n.syncOnline : l10n.syncOffline} · $status',
        style: TextStyle(
          color: st?.phase == PeerPhase.error
              ? AppColors.error
              : AppColors.textSecondary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (st?.phase == PeerPhase.syncing)
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: l10n.syncNow,
              onPressed: online ? () => _syncNow(context, service) : null,
              icon: const Icon(Icons.sync_rounded),
            ),
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => service.unpair(peer.id),
                child: Text(l10n.syncUnpair),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Manual sync: always say how it went (automatic ones stay quiet
  /// unless tracks arrive — see AppNotices).
  Future<void> _syncNow(BuildContext context, SyncService service) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final received = await service.syncWith(peer.id);
      // Received tracks are announced by AppNotices.
      if (received == 0) _notify(messenger, l10n.syncUpToDate(peer.name));
    } on Object catch (e) {
      _notify(
        messenger,
        l10n.syncFailure(
          e is SyncException ? e.reason : SyncFailure.unreachable,
        ),
      );
    }
  }
}

class _CopyAllSwitch extends ConsumerStatefulWidget {
  const _CopyAllSwitch();

  @override
  ConsumerState<_CopyAllSwitch> createState() => _CopyAllSwitchState();
}

class _CopyAllSwitchState extends ConsumerState<_CopyAllSwitch> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(peerStoreProvider);
    return SwitchListTile(
      title: Text(l10n.syncCopyAll),
      subtitle: Text(l10n.syncCopyAllSubtitle),
      value: store.copyAllToPhone,
      onChanged: (v) async {
        await store.setCopyAllToPhone(v);
        setState(() {});
      },
    );
  }
}

/// Small text prompt used for names, codes and addresses.
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  String? hint,
  bool digits = false,
}) => showDialog<String>(
  context: context,
  builder: (context) => _TextPrompt(
    title: title,
    action: action,
    initial: initial,
    hint: hint,
    digits: digits,
  ),
);

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.action,
    required this.initial,
    required this.digits,
    this.hint,
  });

  final String title;
  final String action;
  final String initial;
  final String? hint;
  final bool digits;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
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
        keyboardType: widget.digits ? TextInputType.number : null,
        maxLength: widget.digits ? 6 : null,
        style: widget.digits
            ? const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 24,
                letterSpacing: 6,
              )
            : null,
        decoration: InputDecoration(
          hintText: widget.hint,
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
