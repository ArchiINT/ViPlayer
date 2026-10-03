import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../settings/settings_providers.dart';

/// Stable random id of this installation. Tags data created here (e.g. play
/// history) so synced devices can tell where it came from. Generated once
/// and kept in settings; never derived from hardware identifiers.
final deviceIdProvider = Provider<String>(
  (ref) => deviceId(ref.watch(sharedPreferencesProvider)),
);

String deviceId(SharedPreferences prefs) {
  const key = 'device.id';
  final existing = prefs.getString(key);
  if (existing != null) return existing;
  final id = const Uuid().v4();
  prefs.setString(key, id);
  return id;
}
