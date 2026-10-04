import 'package:flutter/widgets.dart';

import '../download/download_models.dart';
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
    this.downloadFormat = DownloadFormat.m4a,
    this.minTrackSeconds = 0,
    this.longAudioMinutes = 20,
  });

  final AppLanguage language;
  final Accent accent;

  /// Android: include all music indexed by MediaStore, in addition to the
  /// picked folders. Ignored on desktop.
  final bool scanDeviceMusic;

  /// Format of new downloads (opus/mp3 are desktop-only).
  final DownloadFormat downloadFormat;

  /// Tracks shorter than this are hidden everywhere (ringtones, clips).
  /// 0 = show everything.
  final int minTrackSeconds;

  /// Tracks at least this long (audiobooks, podcasts) live in their own
  /// library tab instead of Tracks, and resume where they were left.
  /// 0 = no separate tab.
  final int longAudioMinutes;

  /// Whether [durationMs] counts as long audio under these settings.
  bool isLong(int durationMs) =>
      longAudioMinutes > 0 && durationMs >= longAudioMinutes * 60000;

  AppSettings copyWith({
    AppLanguage? language,
    Accent? accent,
    bool? scanDeviceMusic,
    DownloadFormat? downloadFormat,
    int? minTrackSeconds,
    int? longAudioMinutes,
  }) => AppSettings(
    language: language ?? this.language,
    accent: accent ?? this.accent,
    scanDeviceMusic: scanDeviceMusic ?? this.scanDeviceMusic,
    downloadFormat: downloadFormat ?? this.downloadFormat,
    minTrackSeconds: minTrackSeconds ?? this.minTrackSeconds,
    longAudioMinutes: longAudioMinutes ?? this.longAudioMinutes,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.accent == accent &&
      other.scanDeviceMusic == scanDeviceMusic &&
      other.downloadFormat == downloadFormat &&
      other.minTrackSeconds == minTrackSeconds &&
      other.longAudioMinutes == longAudioMinutes;

  @override
  int get hashCode => Object.hash(
    language,
    accent,
    scanDeviceMusic,
    downloadFormat,
    minTrackSeconds,
    longAudioMinutes,
  );
}
