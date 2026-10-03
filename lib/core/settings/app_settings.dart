import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// UI languages. English is the default.
enum AppLanguage {
  en,
  ru;

  Locale get locale => Locale(name);

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (l) => l.name == code,
    orElse: () => AppLanguage.en,
  );
}

/// Device-local user preferences (not synced between devices).
@immutable
class AppSettings {
  const AppSettings({
    this.language = AppLanguage.en,
    this.accent = Accent.sky,
    this.scanDeviceMusic = true,
  });

  final AppLanguage language;
  final Accent accent;

  /// Android: include all music indexed by MediaStore, in addition to the
  /// picked folders. Ignored on desktop.
  final bool scanDeviceMusic;

  AppSettings copyWith({
    AppLanguage? language,
    Accent? accent,
    bool? scanDeviceMusic,
  }) => AppSettings(
    language: language ?? this.language,
    accent: accent ?? this.accent,
    scanDeviceMusic: scanDeviceMusic ?? this.scanDeviceMusic,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.accent == accent &&
      other.scanDeviceMusic == scanDeviceMusic;

  @override
  int get hashCode => Object.hash(language, accent, scanDeviceMusic);
}
