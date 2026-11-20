import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:media_kit/media_kit.dart' as mk;

import '../download/download_models.dart';

/// Minimal engine for previews: one stream at a time, no queue.
abstract interface class PreviewBackend {
  Stream<bool> get playing;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get completed;

  /// Opens [stream] and starts playing it.
  Future<void> open(PreviewStream stream);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
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
  Future<void> open(PreviewStream stream) =>
      _player.open(mk.Media(stream.url, httpHeaders: stream.headers));
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

/// ExoPlayer (via just_audio), used on Android for HLS streams.
///
/// Leaves audio focus alone, like the libmpv preview: the app pauses its
/// main player itself, and a focus change must not resume it mid-preview.
class ExoPreviewBackend implements PreviewBackend {
  final _player = ja.AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
    useProxyForRequestHeaders: false,
  );

  @override
  Stream<bool> get playing => _player.playingStream;
  @override
  Stream<Duration> get position => _player.positionStream;
  @override
  Stream<Duration> get duration =>
      _player.durationStream.map((d) => d ?? Duration.zero);
  @override
  Stream<bool> get completed => _player.processingStateStream.map(
    (s) => s == ja.ProcessingState.completed,
  );

  @override
  Future<void> open(PreviewStream stream) async {
    await _player.setUrl(stream.url, headers: stream.headers);
    // play() completes only when playback stops: do not wait for it.
    unawaited(_player.play());
  }

  @override
  Future<void> play() async => unawaited(_player.play());
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

/// Sends HLS streams to [hls] and everything else to [main]; events come
/// from whichever is in use.
///
/// Android: its libmpv is built without an HLS demuxer (SoundCloud serves
/// HLS only), while ExoPlayer cannot reach the PC's plain-http previews
/// (cleartext is blocked) — so each plays what it can.
class SplitPreviewBackend implements PreviewBackend {
  SplitPreviewBackend(this._main, this._hls) {
    for (final b in [_main, _hls]) {
      _subs.addAll([
        b.playing.listen((v) => _forward(b, _playing, v)),
        b.position.listen((v) => _forward(b, _position, v)),
        b.duration.listen((v) => _forward(b, _duration, v)),
        b.completed.listen((v) => _forward(b, _completed, v)),
      ]);
    }
  }

  final PreviewBackend _main;
  final PreviewBackend _hls;
  late PreviewBackend _active = _main;
  final _subs = <StreamSubscription<Object?>>[];
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _completed = StreamController<bool>.broadcast();

  void _forward<T>(PreviewBackend from, StreamController<T> to, T value) {
    if (identical(from, _active)) to.add(value);
  }

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Future<void> open(PreviewStream stream) async {
    final next = stream.hls ? _hls : _main;
    if (!identical(next, _active)) await _active.stop();
    _active = next;
    await next.open(stream);
  }

  @override
  Future<void> play() => _active.play();
  @override
  Future<void> pause() => _active.pause();
  @override
  Future<void> seek(Duration position) => _active.seek(position);
  @override
  Future<void> stop() => _active.stop();
  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _main.dispose();
    await _hls.dispose();
    for (final c in [_playing, _position, _duration, _completed]) {
      await c.close();
    }
  }
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
///
/// A result stays "loading" until sound actually starts (the position moves),
/// and fails if that takes longer than [startTimeout].
class PreviewPlayer {
  PreviewPlayer(
    this._backend, {
    this.startTimeout = const Duration(seconds: 15),
  }) {
    _subs.addAll([
      _backend.playing.listen((v) => _set(_state.copyWith(playing: v))),
      _backend.position.listen((v) {
        if (_state.loading && _opened && v > Duration.zero) {
          _startTimer?.cancel();
          _set(_state.copyWith(position: v, loading: false));
        } else {
          _set(_state.copyWith(position: v));
        }
      }),
      _backend.duration.listen((v) => _set(_state.copyWith(duration: v))),
      _backend.completed.listen((done) {
        if (done && _opened) _reset();
      }),
    ]);
  }

  final PreviewBackend _backend;
  final Duration startTimeout;
  final _subs = <StreamSubscription<Object?>>[];
  final _notifier = ValueNotifier(const PreviewState());

  /// The current result's stream is being played (position and end events
  /// before that belong to the previous one).
  bool _opened = false;
  Timer? _startTimer;

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
    _opened = false;
    _startTimer?.cancel();
    _set(PreviewState(key: key, loading: true));
    await _backend.stop();
    try {
      final stream = await resolve();
      // Another result was tapped while this one was resolving.
      if (_state.key != key) return;
      onStart?.call();
      _startTimer = Timer(
        startTimeout,
        () => _fail(key, DownloadFailure.network),
      );
      _opened = true;
      await _backend.open(stream);
    } on DownloadException catch (e) {
      _fail(key, e.reason);
    } on Exception {
      _fail(key, DownloadFailure.network);
    }
  }

  /// Jumps within the current preview (ignored while it is loading).
  Future<void> seek(Duration position) async {
    if (_state.key == null || _state.loading || _state.failure != null) return;
    _set(_state.copyWith(position: position));
    await _backend.seek(position);
  }

  Future<void> stop() async {
    if (_state.key == null) return;
    _reset();
    await _backend.stop();
  }

  void _fail(String key, DownloadFailure reason) {
    if (_state.key != key) return;
    _opened = false;
    _startTimer?.cancel();
    _set(PreviewState(key: key, failure: reason));
    unawaited(_backend.stop());
  }

  void _reset() {
    _opened = false;
    _startTimer?.cancel();
    _set(const PreviewState());
  }

  void _set(PreviewState next) => _notifier.value = next;

  Future<void> dispose() async {
    _startTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _backend.dispose();
    _notifier.dispose();
  }
}
