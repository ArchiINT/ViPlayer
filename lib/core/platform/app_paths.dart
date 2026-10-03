import 'dart:io';

import 'package:path/path.dart' as p;

/// Well-known locations used by the app.
///
/// Downloads deliberately live in the shared Music folder, *not* in
/// app-private storage: Android wipes app-private storage when the app is
/// uninstalled, and the music must survive that. Other players can see it too.
abstract final class AppPaths {
  static const _downloadFolderName = 'ViPlayer';

  /// Android: `/storage/emulated/0/Music/ViPlayer`
  /// Linux:   `$XDG_MUSIC_DIR/ViPlayer`, falling back to `~/Music/ViPlayer`.
  static String downloadDirectory() {
    if (Platform.isAndroid) {
      return p.join('/storage/emulated/0/Music', _downloadFolderName);
    }
    return p.join(_linuxMusicDirectory(), _downloadFolderName);
  }

  static String _linuxMusicDirectory() {
    final home = Platform.environment['HOME'] ?? '';
    final fromEnv = Platform.environment['XDG_MUSIC_DIR'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    // xdg-user-dirs stores it as: XDG_MUSIC_DIR="$HOME/Music"
    final config = File(p.join(home, '.config', 'user-dirs.dirs'));
    if (config.existsSync()) {
      final match = RegExp(
        r'^XDG_MUSIC_DIR="(.+)"$',
        multiLine: true,
      ).firstMatch(config.readAsStringSync());
      if (match != null) return match.group(1)!.replaceAll(r'$HOME', home);
    }
    return p.join(home, 'Music');
  }
}
