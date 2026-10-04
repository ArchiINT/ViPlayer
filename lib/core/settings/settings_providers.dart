import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../download/download_models.dart';
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
  static const _scanDeviceMusicKey = 'settings.scanDeviceMusic';
  static const _downloadFormatKey = 'settings.downloadFormat';
  static const _minTrackKey = 'settings.minTrackSeconds';
  static const _longAudioKey = 'settings.longAudioMinutes';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() => AppSettings(
    language: AppLanguage.fromCode(_prefs.getString(_languageKey)),
    accent: Accent.fromName(_prefs.getString(_accentKey)),
    scanDeviceMusic: _prefs.getBool(_scanDeviceMusicKey) ?? true,
    downloadFormat: DownloadFormat.fromName(
      _prefs.getString(_downloadFormatKey),
    ),
    minTrackSeconds: _prefs.getInt(_minTrackKey) ?? 0,
    longAudioMinutes: _prefs.getInt(_longAudioKey) ?? 20,
  );

  Future<void> setLanguage(AppLanguage language) async {
    state = state.copyWith(language: language);
    await _prefs.setString(_languageKey, language.name);
  }

  Future<void> setAccent(Accent accent) async {
    state = state.copyWith(accent: accent);
    await _prefs.setString(_accentKey, accent.name);
  }

  Future<void> setScanDeviceMusic(bool value) async {
    state = state.copyWith(scanDeviceMusic: value);
    await _prefs.setBool(_scanDeviceMusicKey, value);
  }

  Future<void> setDownloadFormat(DownloadFormat format) async {
    state = state.copyWith(downloadFormat: format);
    await _prefs.setString(_downloadFormatKey, format.name);
  }

  Future<void> setMinTrackSeconds(int seconds) async {
    state = state.copyWith(minTrackSeconds: seconds);
    await _prefs.setInt(_minTrackKey, seconds);
  }

  Future<void> setLongAudioMinutes(int minutes) async {
    state = state.copyWith(longAudioMinutes: minutes);
    await _prefs.setInt(_longAudioKey, minutes);
  }
}
