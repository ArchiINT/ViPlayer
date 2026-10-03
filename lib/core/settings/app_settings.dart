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
    this.accent = NeonAccent.cyan,
  });

  final AppLanguage language;
  final NeonAccent accent;

  AppSettings copyWith({AppLanguage? language, NeonAccent? accent}) =>
      AppSettings(
        language: language ?? this.language,
        accent: accent ?? this.accent,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(language, accent);
}
