import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

import '../platform/app_log.dart';
import 'audio_backend.dart';
import 'player_service.dart';

/// Connects [PlayerService] to the operating system's media controls:
/// Android notification / lock screen / headset buttons, and MPRIS on Linux
/// (desktop media widgets, keyboard media keys, `playerctl`).
class ViAudioHandler extends BaseAudioHandler with SeekHandler {
  ViAudioHandler(this._player) {
    _player.snapshot.addListener(_sync);
    _sync();
  }

  final PlayerService _player;
  String? _lastTrackId;

  /// Android keeps the app a foreground service during a pause: Android 16
  /// mutes apps that start playing from the background, which is exactly
  /// what resuming after a call / TikTok / a notification is. A long pause
  /// leaves the foreground (and releases the wake lock); the notification
  /// stays, and playing again re-enters the foreground.
  static const releaseAfterPause = Duration(minutes: 10);
  static const _serviceChannel = MethodChannel('viplayer/playback_service');
  Timer? _releaseTimer;

  static const _shuffleAction = 'viplayer.shuffle';
  static const _repeatAction = 'viplayer.repeat';

  /// Starts the system integration. Never fatal: without it (no D-Bus
  /// session, unsupported platform) the app still plays music.
  static Future<void> start(PlayerService player) async {
    try {
      await AudioService.init(
        builder: () => ViAudioHandler(player),
        config: const AudioServiceConfig(
          // Also shown as the player's name by MPRIS on Linux.
          androidNotificationChannelId: 'ViPlayer',
          androidNotificationChannelName: 'Playback',
          // Stay foreground while paused (see [releaseAfterPause]).
          androidStopForegroundOnPause: false,
        ),
      );
    } catch (error) {
      AppLog.error('system media controls unavailable', error);
    }
  }

  void _sync() {
    final s = _player.snapshot.value;
    final track = s.current;

    if (s.playing) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
    } else if (Platform.isAndroid && _releaseTimer == null) {
      _releaseTimer = Timer(releaseAfterPause, () {
        if (_player.snapshot.value.playing) return;
        unawaited(
          _serviceChannel
              .invokeMethod<bool>('releaseForeground')
              .catchError((Object e) {
                AppLog.error('leaving foreground after a pause', e);
                return false;
              }),
        );
      });
    }

    if (track?.id != _lastTrackId) {
      _lastTrackId = track?.id;
      mediaItem.add(
        track == null
            ? null
            : MediaItem(
                id: track.path,
                title: track.title,
                artist: track.artist.isEmpty ? null : track.artist,
                album: track.album.isEmpty ? null : track.album,
                duration: Duration(milliseconds: track.durationMs),
                artUri: switch (track.coverPath) {
                  null => null,
                  // Streamed from another device: a URL, not a file.
                  final c when c.startsWith('http') => Uri.parse(c),
                  final c => Uri.file(c),
                },
              ),
      );
    } else if (track != null &&
        s.duration > Duration.zero &&
        mediaItem.value?.duration != s.duration) {
      mediaItem.add(mediaItem.value?.copyWith(duration: s.duration));
    }

    playbackState.add(
      PlaybackState(
        // Compact view (lock screen): previous, play/pause, next; Android
        // 13+ adds the two custom controls (shuffle, repeat) beside them.
        controls: [
          MediaControl.skipToPrevious,
          if (s.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.custom(
            androidIcon: s.shuffle
                ? 'drawable/vp_shuffle_on'
                : 'drawable/vp_shuffle_off',
            label: 'Shuffle',
            name: _shuffleAction,
          ),
          MediaControl.custom(
            androidIcon: switch (s.repeat) {
              PlaybackRepeat.off => 'drawable/vp_repeat_off',
              PlaybackRepeat.all => 'drawable/vp_repeat_all',
              PlaybackRepeat.one => 'drawable/vp_repeat_one',
            },
            label: 'Repeat',
            name: _repeatAction,
          ),
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: track == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: s.playing,
        // The OS extrapolates the position from this value while playing.
        updatePosition: _player.currentPosition,
        shuffleMode: s.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (s.repeat) {
          PlaybackRepeat.off => AudioServiceRepeatMode.none,
          PlaybackRepeat.all => AudioServiceRepeatMode.all,
          PlaybackRepeat.one => AudioServiceRepeatMode.one,
        },
      ),
    );
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case _shuffleAction:
        await _player.toggleShuffle();
      case _repeatAction:
        await _player.cycleRepeat();
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.pause();

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> skipToQueueItem(int index) => _player.jumpTo(index);

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _sync(); // report the new position right away
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final wanted = shuffleMode != AudioServiceShuffleMode.none;
    if (wanted != _player.snapshot.value.shuffle) {
      await _player.toggleShuffle();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final wanted = switch (repeatMode) {
      AudioServiceRepeatMode.none => PlaybackRepeat.off,
      AudioServiceRepeatMode.one => PlaybackRepeat.one,
      _ => PlaybackRepeat.all,
    };
    while (_player.snapshot.value.repeat != wanted) {
      await _player.cycleRepeat();
      // Wait for the engine to report the change before checking again.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
