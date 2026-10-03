import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/platform/app_directories.dart';
import 'core/settings/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolved before the first frame so theme, language and paths are
  // available synchronously everywhere — nothing flickers on startup.
  final (prefs, directories) = await (
    SharedPreferences.getInstance(),
    AppDirectories.resolve(),
  ).wait;

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDirectoriesProvider.overrideWithValue(directories),
      ],
      child: const ViPlayerApp(),
    ),
  );
}
