import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../database/database_backup.dart';
import '../platform/app_directories.dart';
import '../sync/sync_providers.dart';
import 'update_service.dart';

/// App updates from a paired PC; Android only (null elsewhere).
final updateServiceProvider = Provider<UpdateService?>((ref) {
  if (!Platform.isAndroid) return null;
  final dirs = ref.watch(appDirectoriesProvider);
  final db = ref.watch(appDatabaseProvider);
  final service = UpdateService(
    sync: ref.watch(syncServiceProvider),
    cacheDirectory: p.join(dirs.cache, 'update'),
    installer: const AndroidUpdateInstaller(),
    backup: () =>
        backupDatabase(db, p.join(dirs.support, 'backups'), reason: 'update'),
  );
  ref.onDispose(service.dispose);
  return service;
});

final updateStateProvider = NotifierProvider<UpdateStateNotifier, UpdateState>(
  UpdateStateNotifier.new,
);

class UpdateStateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() {
    final service = ref.watch(updateServiceProvider);
    if (service == null) return const UpdateState();
    final state = service.state;
    void listener() => this.state = state.value;
    state.addListener(listener);
    ref.onDispose(() => state.removeListener(listener));
    return state.value;
  }
}
