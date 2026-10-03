import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import 'app_settings.dart';

/// Loaded once in `main()` and injected via a ProviderScope override, so
/// settings are available synchronously from the very first frame.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Reads and persists [AppSettings] in SharedPreferences.
class SettingsController extends Notifier<AppSettings> {
  static const _languageKey = 'settings.language';
  static const _accentKey = 'settings.accent';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() => AppSettings(
    language: AppLanguage.fromCode(_prefs.getString(_languageKey)),
    accent: NeonAccent.fromName(_prefs.getString(_accentKey)),
  );

  Future<void> setLanguage(AppLanguage language) async {
    state = state.copyWith(language: language);
    await _prefs.setString(_languageKey, language.name);
  }

  Future<void> setAccent(NeonAccent accent) async {
    state = state.copyWith(accent: accent);
    await _prefs.setString(_accentKey, accent.name);
  }
}
