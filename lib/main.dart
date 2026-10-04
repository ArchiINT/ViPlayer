import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/download/download_service.dart';
import 'core/platform/app_directories.dart';
import 'core/platform/app_log.dart';
import 'core/player/audio_backend.dart';
import 'core/player/audio_focus.dart';
import 'core/player/audio_handler.dart';
import 'core/player/player_providers.dart';
import 'core/player/player_service.dart';
import 'core/settings/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKitBackend.ensureInitialized();

  // Resolved before the first frame so theme, language and paths are
  // available synchronously everywhere — nothing flickers on startup.
  final (prefs, directories) = await (
    SharedPreferences.getInstance(),
    AppDirectories.resolve(),
  ).wait;

  // Errors anywhere end up in the log file (Settings → About shows where).
  await AppLog.init(directories.support);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.error('flutter', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('uncaught', error, stack);
    return true;
  };

  // Download previews are throwaway: each session starts with none.
  await DownloadService.clearPreviewCache(directories.previews);

  // The player lives outside the widget tree: the system media controls
  // (notification, MPRIS) talk to it even when no screen is shown.
  final player = PlayerService(MediaKitBackend(), prefs);
  await ViAudioHandler.start(player);
  // Android: headset buttons, pause on calls and when headphones unplug.
  await AudioFocus(player).start();

  // Bundled fonts' licenses join the package licenses in the About screen.
  LicenseRegistry.addLicense(() async* {
    for (final (font, file) in [
      ('Inter', 'OFL-Inter.txt'),
      ('JetBrains Mono', 'OFL-JetBrainsMono.txt'),
      ('Orbitron', 'OFL-Orbitron.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDirectoriesProvider.overrideWithValue(directories),
        playerServiceProvider.overrideWithValue(player),
      ],
      child: const ViPlayerApp(),
    ),
  );
}
