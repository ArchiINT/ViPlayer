import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../platform/app_log.dart';
import 'player_service.dart';

/// Android audio focus for the player.
///
/// media_kit outputs audio directly and does not ask Android for focus, so
/// without this:
///  * headset / Bluetooth buttons may go to another app (Android sends
///    media buttons to the app holding — or last holding — focus);
///  * music keeps playing through a call, and on top of other apps;
///  * unplugging headphones does not pause.
class AudioFocus {
  AudioFocus(this._player);

  final PlayerService _player;
  AudioSession? _session;
  final _subs = <StreamSubscription<Object?>>[];

  /// Paused by an interruption (call, other app) — resume when it ends.
  bool _resumeAfterInterruption = false;

  /// Volume before ducking, restored afterwards.
  double? _volumeBeforeDuck;
  bool _wasPlaying = false;

  static const _duckedVolumeFactor = 0.3;

  Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _session = session;
      _subs.addAll([
        session.interruptionEventStream.listen(handleInterruption),
        session.becomingNoisyEventStream.listen((_) => handleBecomingNoisy()),
      ]);
      _player.snapshot.addListener(_onPlayer);
    } catch (e, stack) {
      AppLog.error('audio focus unavailable', e, stack);
    }
  }

  /// Ask for focus whenever playback starts; give up playing if refused
  /// (e.g. during a phone call).
  void _onPlayer() {
    final playing = _player.snapshot.value.playing;
    if (playing && !_wasPlaying) {
      unawaited(
        _session?.setActive(true).then((granted) {
          if (!granted) _player.pause();
        }),
      );
    }
    _wasPlaying = playing;
  }

  /// Headphones unplugged / Bluetooth disconnected.
  @visibleForTesting
  void handleBecomingNoisy() => _player.pause();

  @visibleForTesting
  void handleInterruption(AudioInterruptionEvent event) {
    final playing = _player.snapshot.value.playing;
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // Short sound (navigation, notification): play quieter.
          if (playing && _volumeBeforeDuck == null) {
            _volumeBeforeDuck = _player.snapshot.value.volume;
            _player.setVolume(_volumeBeforeDuck! * _duckedVolumeFactor);
          }
        case AudioInterruptionType.pause || AudioInterruptionType.unknown:
          // Call or another player: pause, maybe resume afterwards.
          _resumeAfterInterruption =
              playing && event.type == AudioInterruptionType.pause;
          if (playing) _player.pause();
      }
    } else {
      if (_volumeBeforeDuck case final volume?) {
        _player.setVolume(volume);
        _volumeBeforeDuck = null;
      }
      if (_resumeAfterInterruption) {
        _resumeAfterInterruption = false;
        _player.play();
      }
    }
  }

  Future<void> dispose() async {
    _player.snapshot.removeListener(_onPlayer);
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
