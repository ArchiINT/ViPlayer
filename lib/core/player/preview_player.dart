import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import '../download/download_models.dart';

/// Minimal engine for previews: one URL at a time, no queue.
abstract interface class PreviewBackend {
  Stream<bool> get playing;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get completed;

  Future<void> open(String url, Map<String, String> headers);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

class MediaKitPreviewBackend implements PreviewBackend {
  final _player = mk.Player(
    configuration: const mk.PlayerConfiguration(
      title: 'ViPlayer preview',
      vo: 'null',
    ),
  );

  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Future<void> open(String url, Map<String, String> headers) =>
      _player.open(mk.Media(url, httpHeaders: headers));
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

@immutable
class PreviewState {
  const PreviewState({
    this.key,
    this.loading = false,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.failure,
  });

  /// Which result is being previewed (see [PreviewPlayer.keyOf]).
  final String? key;
  final bool loading;
  final bool playing;
  final Duration position;
  final Duration duration;
  final DownloadFailure? failure;

  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  PreviewState copyWith({
    bool? loading,
    bool? playing,
    Duration? position,
    Duration? duration,
  }) => PreviewState(
    key: key,
    loading: loading ?? this.loading,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    failure: failure,
  );
}

/// Plays search results before they are downloaded, separately from the
/// main player so the user's queue is never touched.
class PreviewPlayer {
  PreviewPlayer(this._backend) {
    _subs.addAll([
      _backend.playing.listen((v) => _set(_state.copyWith(playing: v))),
      _backend.position.listen((v) => _set(_state.copyWith(position: v))),
      _backend.duration.listen((v) => _set(_state.copyWith(duration: v))),
      _backend.completed.listen((done) {
        if (done) _set(const PreviewState());
      }),
    ]);
  }

  final PreviewBackend _backend;
  final _subs = <StreamSubscription<Object?>>[];
  final _notifier = ValueNotifier(const PreviewState());

  /// Called when a preview starts (the app pauses the main player).
  VoidCallback? onStart;

  ValueListenable<PreviewState> get state => _notifier;
  PreviewState get _state => _notifier.value;

  static String keyOf(DownloadCandidate c) => '${c.service.name}:${c.sourceId}';

  /// Play / pause [c]; switching to another result stops the current one.
  /// [resolve] fetches the stream (may take a second or two).
  Future<void> toggle(
    DownloadCandidate c,
    Future<PreviewStream> Function() resolve,
  ) async {
    final key = keyOf(c);
    if (_state.key == key && !_state.loading && _state.failure == null) {
      return _state.playing ? _backend.pause() : _backend.play();
    }

    // Show "loading" at once; the tap must feel instant.
    _set(PreviewState(key: key, loading: true));
    await _backend.stop();
    try {
      final stream = await resolve();
      // Another result was tapped while this one was resolving.
      if (_state.key != key) return;
      onStart?.call();
      await _backend.open(stream.url, stream.headers);
      _set(_state.copyWith(loading: false));
    } on DownloadException catch (e) {
      if (_state.key == key) _set(PreviewState(key: key, failure: e.reason));
    } on Exception {
      if (_state.key == key) {
        _set(PreviewState(key: key, failure: DownloadFailure.network));
      }
    }
  }

  Future<void> stop() async {
    if (_state.key == null) return;
    _set(const PreviewState());
    await _backend.stop();
  }

  void _set(PreviewState next) => _notifier.value = next;

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _backend.dispose();
    _notifier.dispose();
  }
}
