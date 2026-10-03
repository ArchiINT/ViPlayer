import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/library_models.dart';
import 'audio_backend.dart';

/// Everything the UI shows about playback except the position, which
/// changes many times per second and has its own stream.
@immutable
class PlayerSnapshot {
  const PlayerSnapshot({
    this.queue = const [],
    this.index = -1,
    this.playing = false,
    this.shuffle = false,
    this.repeat = PlaybackRepeat.off,
    this.duration = Duration.zero,
    this.volume = 100,
  });

  /// In play order (shuffled if [shuffle] is on).
  final List<LibraryTrack> queue;
  final int index;
  final bool playing;
  final bool shuffle;
  final PlaybackRepeat repeat;
  final Duration duration;
  final double volume;

  LibraryTrack? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;

  bool get hasNext => index < queue.length - 1 || repeat != PlaybackRepeat.off;

  PlayerSnapshot copyWith({
    List<LibraryTrack>? queue,
    int? index,
    bool? playing,
    bool? shuffle,
    PlaybackRepeat? repeat,
    Duration? duration,
    double? volume,
  }) => PlayerSnapshot(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    playing: playing ?? this.playing,
    shuffle: shuffle ?? this.shuffle,
    repeat: repeat ?? this.repeat,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
  );
}

/// The music player: queue, transport controls, and a session that survives
/// app restarts. Plain Dart (no Flutter widgets), shared by the UI and the
/// system media controls (see ViAudioHandler).
///
/// The engine owns the play order (it shuffles and repeats natively, which
/// keeps playback gapless); this class maps engine paths back to tracks.
class PlayerService {
  PlayerService(this._backend, this._prefs) {
    _subscriptions.addAll([
      _backend.playlist.listen(_onPlaylist),
      _backend.playing.listen((v) => _update(_state.copyWith(playing: v))),
      _backend.shuffle.listen((v) => _update(_state.copyWith(shuffle: v))),
      _backend.repeat.listen((v) => _update(_state.copyWith(repeat: v))),
      _backend.volume.listen((v) => _update(_state.copyWith(volume: v))),
      _backend.duration.listen(_onDuration),
    ]);
    _saveTimer = Timer.periodic(_saveInterval, (_) => _saveSession());
  }

  final AudioBackend _backend;
  final SharedPreferences _prefs;

  /// Called when the engine reports a track length that differs from the
  /// tags (tag estimates are sometimes off). Used to fix the database.
  void Function(LibraryTrack track, Duration actual)? onDurationMeasured;

  /// "Previous" restarts the current track if it has played longer than this.
  static const restartThreshold = Duration(seconds: 3);

  static const _sessionKey = 'player.session';
  static const _saveInterval = Duration(seconds: 5);
  static const _maxSavedQueue = 2000;

  final _subscriptions = <StreamSubscription<Object?>>[];
  late final Timer _saveTimer;

  /// Engine path -> track, for every track handed to the engine.
  final _tracksByPath = <String, LibraryTrack>{};

  final _snapshot = ValueNotifier(const PlayerSnapshot());
  PlayerSnapshot get _state => _snapshot.value;

  ValueListenable<PlayerSnapshot> get snapshot => _snapshot;
  Stream<Duration> get position => _backend.position;
  Duration get currentPosition => _backend.currentPosition;

  // ---------------------------------------------------------------- control

  /// Replaces the queue with [tracks] and plays [startIndex].
  Future<void> playQueue(
    List<LibraryTrack> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    _remember(tracks);
    // A fresh queue starts in order; shuffle stays as the user left it.
    final shuffled = _state.shuffle;
    if (shuffled) await _backend.setShuffle(false);
    await _backend.open([for (final t in tracks) t.path], index: startIndex);
    if (shuffled) await _backend.setShuffle(true);
  }

  Future<void> playOrPause() => _backend.playOrPause();
  Future<void> play() => _backend.play();
  Future<void> pause() => _backend.pause();
  Future<void> next() => _backend.next();
  Future<void> seek(Duration position) => _backend.seek(position);
  Future<void> jumpTo(int index) => _backend.jump(index);

  /// Restarts the current track if it has been playing for a while,
  /// otherwise goes to the previous one — like every music player.
  Future<void> previous() async {
    if (_backend.currentPosition > restartThreshold || _state.index <= 0) {
      await _backend.seek(Duration.zero);
    } else {
      await _backend.previous();
    }
  }

  Future<void> toggleShuffle() => _backend.setShuffle(!_state.shuffle);

  /// off -> all -> one -> off
  Future<void> cycleRepeat() => _backend.setRepeat(
    PlaybackRepeat.values[(_state.repeat.index + 1) %
        PlaybackRepeat.values.length],
  );

  Future<void> setVolume(double volume) =>
      _backend.setVolume(volume.clamp(0, 100));

  /// Inserts [track] right after the current one.
  Future<void> playNext(LibraryTrack track) async {
    if (_state.current == null) return playQueue([track]);
    _remember([track]);
    // Read before awaiting: the playlist stream may update in between.
    final last = _state.queue.length; // index the appended entry will get
    final target = _state.index + 1;
    await _backend.add(track.path);
    if (last > target) await _backend.move(last, target);
  }

  /// Appends [track] to the end of the queue.
  Future<void> addToQueue(LibraryTrack track) async {
    if (_state.current == null) return playQueue([track]);
    _remember([track]);
    await _backend.add(track.path);
  }

  Future<void> removeAt(int index) => _backend.remove(index);

  /// Moves the entry at [from] so that it ends up at index [to].
  Future<void> reorder(int from, int to) async {
    if (from == to) return;
    // mpv moves an entry *before* the target entry, so moving down needs
    // the entry after the destination as target.
    await _backend.move(from, from < to ? to + 1 : to);
  }

  // ---------------------------------------------------------------- session

  /// Restores the last session (queue, track, position, modes, volume)
  /// without starting playback. Tracks that no longer exist are skipped.
  Future<void> restoreSession(Map<String, LibraryTrack> tracksByPath) async {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null || _state.current != null) return;
    final Map<String, Object?> session;
    try {
      session = jsonDecode(raw) as Map<String, Object?>;
    } on FormatException {
      return;
    }

    final volume = (session['volume'] as num?)?.toDouble();
    if (volume != null) await _backend.setVolume(volume);
    final repeat = PlaybackRepeat.values.asNameMap()[session['repeat']];
    if (repeat != null) await _backend.setRepeat(repeat);

    final paths = (session['paths'] as List<Object?>? ?? const [])
        .cast<String>();
    final savedIndex = (session['index'] as num?)?.toInt() ?? 0;
    final currentPath = savedIndex < paths.length ? paths[savedIndex] : null;
    final tracks = [for (final p in paths) ?tracksByPath[p]];
    if (tracks.isEmpty) return;
    final index = tracks.indexWhere((t) => t.path == currentPath);

    _remember(tracks);
    final positionMs = (session['positionMs'] as num?)?.toInt() ?? 0;
    final resumeAt = index >= 0 && positionMs > 0
        ? Duration(milliseconds: positionMs)
        : null;
    // The engine accepts seeks only once the file is loaded (duration
    // known). Listen before opening so the event cannot be missed.
    // Never throws: false if the file did not load (it then simply starts
    // from the beginning).
    final loaded = _backend.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(const Duration(seconds: 3))
        .then((_) => true, onError: (Object _) => false);
    await _backend.open(
      [for (final t in tracks) t.path],
      index: index < 0 ? 0 : index,
      play: false,
    );
    if (await loaded && resumeAt != null) await _backend.seek(resumeAt);
  }

  void _saveSession() {
    final s = _state;
    if (s.current == null) return;
    // Keep the saved queue bounded, centred on the current track.
    final start = (s.index - _maxSavedQueue ~/ 2).clamp(0, s.queue.length);
    final end = (start + _maxSavedQueue).clamp(0, s.queue.length);
    unawaited(
      _prefs.setString(
        _sessionKey,
        jsonEncode({
          'paths': [for (final t in s.queue.sublist(start, end)) t.path],
          'index': s.index - start,
          'positionMs': _backend.currentPosition.inMilliseconds,
          'repeat': s.repeat.name,
          'volume': s.volume,
        }),
      ),
    );
  }

  // ---------------------------------------------------------------- engine

  void _remember(Iterable<LibraryTrack> tracks) {
    for (final t in tracks) {
      _tracksByPath[t.path] = t;
    }
  }

  void _onPlaylist(BackendPlaylist playlist) {
    final queue = [for (final p in playlist.paths) ?_tracksByPath[p]];
    final inRange =
        playlist.index >= 0 && playlist.index < playlist.paths.length;
    final current = inRange
        ? _tracksByPath[playlist.paths[playlist.index]]
        : null;
    // Normally every path is known and indexes match the engine's one to
    // one (the same song may be queued twice, so never search by value).
    final index = current == null
        ? -1
        : queue.length == playlist.paths.length
        ? playlist.index
        : queue.indexOf(current);
    final trackChanged = current?.id != _state.current?.id;
    _update(
      _state.copyWith(
        queue: queue,
        index: index,
        duration: trackChanged ? Duration.zero : null,
      ),
    );
    if (trackChanged) _saveSession();
  }

  void _onDuration(Duration duration) {
    _update(_state.copyWith(duration: duration));
    final track = _state.current;
    if (track == null || duration == Duration.zero) return;
    final diff = (duration.inMilliseconds - track.durationMs).abs();
    if (diff > 1500) onDurationMeasured?.call(track, duration);
  }

  void _update(PlayerSnapshot next) => _snapshot.value = next;

  /// Replaces cached track objects (e.g. a track was liked or renamed) so the
  /// queue shows fresh data. Paths that are no longer in the library stay as
  /// they were — the engine is already playing them.
  void refreshTracks(Map<String, LibraryTrack> tracksByPath) {
    var changed = false;
    for (final entry in tracksByPath.entries) {
      final old = _tracksByPath[entry.key];
      if (old != null && old != entry.value) {
        _tracksByPath[entry.key] = entry.value;
        changed = true;
      }
    }
    if (!changed) return;
    _update(
      _state.copyWith(
        queue: [for (final t in _state.queue) _tracksByPath[t.path] ?? t],
      ),
    );
  }

  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _saveSession();
    _saveTimer.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _backend.dispose();
    _snapshot.dispose();
  }
}
