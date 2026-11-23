import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/library_models.dart';
import 'audio_backend.dart';
import 'play_order.dart';

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

  /// In play order: recently played, the current track, then up next.
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
/// The queue is endless: after the current track there are always at least
/// [upNextTarget] tracks, topped up from the list playback started from
/// ([PlayOrder], in order or shuffled). Tracks the user adds come on top and
/// are never trimmed; only the automatic part is refilled. The engine plays
/// this queue as a plain playlist (gapless); this class maps its paths back
/// to tracks.
class PlayerService {
  PlayerService(this._backend, this._prefs) {
    _subscriptions.addAll([
      _backend.playlist.listen(_onPlaylist),
      _backend.playing.listen((v) => _update(_state.copyWith(playing: v))),
      _backend.repeat.listen((v) => _update(_state.copyWith(repeat: v))),
      _backend.volume.listen((v) => _update(_state.copyWith(volume: v))),
      _backend.duration.listen(_onDuration),
      _backend.position.listen((p) => _lastPosition = p),
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

  /// Tracks kept after the current one (more if the user added them).
  static const upNextTarget = 20;

  /// Played tracks kept before the current one, for "previous".
  static const historyKept = 50;

  static final _random = math.Random();
  static const _sessionKey = 'player.session';
  static const _resumeKey = 'player.resume';
  static const _maxResumeEntries = 200;

  /// Long audio (books, podcasts) resumes where it was left; set by the
  /// app from the "long audio" setting. Null: nothing resumes.
  bool Function(LibraryTrack track)? isLong;

  Duration _lastPosition = Duration.zero;
  static const _saveInterval = Duration(seconds: 5);
  static const _maxSavedQueue = 2000;

  final _subscriptions = <StreamSubscription<Object?>>[];
  late final Timer _saveTimer;

  /// Engine path -> track, for every track handed to the engine.
  final _tracksByPath = <String, LibraryTrack>{};

  /// Where automatic tracks come from; null before anything was played.
  PlayOrder? _order;

  /// The engine's playlist as this class last changed it. The engine
  /// reports changes asynchronously, so queue arithmetic uses this model,
  /// never the last report: [_paths], per entry whether the user added it
  /// ([_manual], kept when the automatic part is rebuilt), and the current
  /// entry ([_index], also moved by the engine as tracks end).
  List<String> _paths = [];
  List<bool> _manual = [];
  int _index = -1;

  /// Queue changes in flight; while > 0 engine reports may be stale.
  int _changing = 0;

  /// Serialises queue changes (each one inspects the result of the last).
  Future<void> _filling = Future.value();

  final _snapshot = ValueNotifier(const PlayerSnapshot());
  PlayerSnapshot get _state => _snapshot.value;

  ValueListenable<PlayerSnapshot> get snapshot => _snapshot;
  Stream<Duration> get position => _backend.position;
  Duration get currentPosition => _backend.currentPosition;

  // ---------------------------------------------------------------- control

  /// Plays [tracks] from [startIndex]; they become the source of the
  /// automatic queue (in order or shuffled, as the shuffle button is).
  Future<void> playQueue(
    List<LibraryTrack> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    _remember(tracks);
    final paths = [for (final t in tracks) t.path];
    final start = startIndex.clamp(0, paths.length - 1);
    final shuffle = _state.shuffle;
    _order = PlayOrder(paths, shuffle: shuffle, start: start);
    // In order, the tracks before the start can be gone back to.
    final history = shuffle
        ? const <String>[]
        : paths.sublist(math.max(0, start - historyKept), start);
    final queue = [...history, paths[start], ..._order!.take(upNextTarget)];
    await _queued(() {
      _paths = queue;
      _manual = List.filled(queue.length, false, growable: true);
      _index = history.length;
      return _backend.open(queue, index: history.length);
    });
    await _topUp();
  }

  /// Plays [tracks] in random order (turns shuffle on).
  Future<void> shufflePlay(List<LibraryTrack> tracks) async {
    if (tracks.isEmpty) return;
    _update(_state.copyWith(shuffle: true));
    await playQueue(tracks, startIndex: _random.nextInt(tracks.length));
  }

  Future<void> playOrPause() => _backend.playOrPause();
  Future<void> play() => _backend.play();
  Future<void> pause() => _backend.pause();
  Future<void> seek(Duration position) => _backend.seek(position);

  Future<void> next() async {
    await _backend.next();
    await _topUp();
  }

  Future<void> jumpTo(int index) async {
    await _backend.jump(index);
    await _topUp();
  }

  /// Restarts the current track if it has been playing for a while,
  /// otherwise goes to the previous one — like every music player.
  Future<void> previous() async {
    if (_backend.currentPosition > restartThreshold || _state.index <= 0) {
      await _backend.seek(Duration.zero);
    } else {
      await _backend.previous();
    }
  }

  /// Switches between in-order and shuffled play. The automatic part of up
  /// next is rebuilt from the current track; tracks the user added stay.
  Future<void> toggleShuffle() async {
    final shuffle = !_state.shuffle;
    _update(_state.copyWith(shuffle: shuffle));
    final order = _order;
    final current = _state.current;
    if (order == null || current == null) return;
    order.setShuffle(shuffle, current: current.path);
    await _queued(() async {
      for (var i = _paths.length - 1; i > _index; i--) {
        if (!_manual[i]) await _removeEntry(i);
      }
    });
    await _topUp();
  }

  /// off -> one -> off. (There is no "repeat all": the queue never ends.)
  Future<void> cycleRepeat() => _backend.setRepeat(
    _state.repeat == PlaybackRepeat.off
        ? PlaybackRepeat.one
        : PlaybackRepeat.off,
  );

  Future<void> setVolume(double volume) =>
      _backend.setVolume(volume.clamp(0, 100));

  /// Inserts [track] right after the current one.
  Future<void> playNext(LibraryTrack track) async {
    if (_state.current == null) return _playAlone(track);
    _remember([track]);
    await _queued(() async {
      // The index the appended entry will get.
      final last = _paths.length;
      final target = _index + 1;
      await _addEntry(track.path, manual: true);
      if (last > target) await _moveEntry(last, target);
    });
  }

  /// Appends [track] to the end of the queue.
  Future<void> addToQueue(LibraryTrack track) async {
    if (_state.current == null) return _playAlone(track);
    _remember([track]);
    await _queued(() => _addEntry(track.path, manual: true));
  }

  /// A track queued while nothing plays just plays: no list to continue
  /// from, so no automatic tracks follow it.
  Future<void> _playAlone(LibraryTrack track) async {
    _remember([track]);
    _order = null;
    await _queued(() {
      _paths = [track.path];
      _manual = [true];
      _index = 0;
      return _backend.open(_paths);
    });
  }

  Future<void> removeAt(int index) async {
    await _queued(() => _removeEntry(index));
    await _topUp();
  }

  /// Removes every queue entry playing [path] (its file is being deleted).
  /// If it is the current track, playback moves on to the next one.
  Future<void> removeTrack(String path) async {
    _order?.remove(path);
    await _queued(() async {
      for (var i = _paths.length - 1; i >= 0; i--) {
        if (_paths[i] == path) await _removeEntry(i);
      }
    });
    _tracksByPath.remove(path);
    await _topUp();
  }

  /// Moves the entry at [from] so that it ends up at index [to].
  Future<void> reorder(int from, int to) async {
    if (from == to) return;
    // mpv moves an entry *before* the target entry, so moving down needs
    // the entry after the destination as target.
    await _queued(() => _moveEntry(from, from < to ? to + 1 : to));
  }

  // ------------------------------------------------------------------ queue
  // Every playlist change goes through these (inside [_queued]), so the
  // model stays equal to the engine's playlist.

  Future<void> _addEntry(String path, {required bool manual}) {
    _paths.add(path);
    _manual.add(manual);
    return _backend.add(path);
  }

  Future<void> _removeEntry(int index) {
    _paths.removeAt(index);
    _manual.removeAt(index);
    // Removing the current entry plays the next one, now at the same index.
    if (index < _index) _index--;
    return _backend.remove(index);
  }

  /// mpv semantics: the entry at [from] ends up before the one at [to].
  Future<void> _moveEntry(int from, int to) {
    final dest = from < to ? to - 1 : to;
    _paths.insert(dest, _paths.removeAt(from));
    _manual.insert(dest, _manual.removeAt(from));
    if (_index == from) {
      _index = dest;
    } else {
      if (from < _index) _index--;
      if (dest <= _index) _index++;
    }
    return _backend.move(from, to);
  }

  /// Runs [change] after any queue work already in progress.
  Future<void> _queued(Future<void> Function() change) {
    final run = _filling.then((_) async {
      _changing++;
      try {
        await change();
      } finally {
        _changing--;
      }
    });
    _filling = run.catchError((Object _) {});
    return run;
  }

  /// Drops old history and refills up next to [upNextTarget] from the play
  /// order. Called after anything that may have shortened the queue.
  Future<void> _topUp() => _queued(() async {
    final order = _order;
    if (order == null || _index < 0) return;
    for (var extra = _index - historyKept; extra > 0; extra--) {
      await _removeEntry(0);
    }
    final upcoming = _paths.length - _index - 1;
    final missing = upNextTarget - upcoming;
    if (missing <= 0) return;
    for (final path in order.take(missing)) {
      await _addEntry(path, manual: false);
    }
  });

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
    // "all" from older versions is no longer a mode (the queue never ends).
    final repeat = PlaybackRepeat.values.asNameMap()[session['repeat']];
    if (repeat != null) await _backend.setRepeat(repeat);

    final paths = (session['paths'] as List<Object?>? ?? const [])
        .cast<String>();
    final savedIndex = (session['index'] as num?)?.toInt() ?? 0;
    final currentPath = savedIndex < paths.length ? paths[savedIndex] : null;
    final manual = {
      for (final i in (session['manual'] as List<Object?>? ?? const []))
        if (i is int && i < paths.length) paths[i],
    };
    final tracks = [for (final p in paths) ?tracksByPath[p]];
    if (tracks.isEmpty) return;
    final index = tracks.indexWhere((t) => t.path == currentPath);

    _remember(tracks);
    final savedOrder = session['order'];
    _order = switch (savedOrder) {
      final Map<String, Object?> json => PlayOrder.fromJson(
        json,
        tracksByPath.containsKey,
      ),
      false => null,
      // Sessions from before the endless queue: continue through what was
      // queued, in order.
      _ => PlayOrder(
        [for (final t in tracks) t.path],
        shuffle: false,
        start: index < 0 ? 0 : index,
      ),
    };
    if (_order case final order?) {
      _remember([for (final p in order.paths) ?tracksByPath[p]]);
      _update(_state.copyWith(shuffle: order.shuffle));
    }
    _manual = [for (final t in tracks) manual.contains(t.path)];
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
    await _queued(() {
      _paths = [for (final t in tracks) t.path];
      _index = index < 0 ? 0 : index;
      return _backend.open(_paths, index: _index, play: false);
    });
    if (await loaded && resumeAt != null) await _backend.seek(resumeAt);
    await _topUp();
  }

  void _saveSession() {
    final s = _state;
    if (s.current == null) return;
    _rememberResume(s.current, _backend.currentPosition);
    // Keep the saved queue bounded, centred on the current track.
    final start = (s.index - _maxSavedQueue ~/ 2).clamp(0, s.queue.length);
    final end = (start + _maxSavedQueue).clamp(0, s.queue.length);
    unawaited(
      _prefs.setString(
        _sessionKey,
        jsonEncode({
          'paths': [for (final t in s.queue.sublist(start, end)) t.path],
          'index': s.index - start,
          'manual': [
            for (var i = start; i < end && i < _manual.length; i++)
              if (_manual[i]) i - start,
          ],
          // false: a lone queued track, nothing to continue from.
          'order': _order?.toJson() ?? false,
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
    if (listEquals(playlist.paths, _paths)) {
      _index = playlist.index; // tracks end and are skipped in the engine
    } else if (_changing == 0) {
      // Not a report lagging behind our own change: the engine's playlist
      // is the truth (flags kept for entries that are still in place).
      _manual = [
        for (final (i, p) in playlist.paths.indexed)
          i < _paths.length && _paths[i] == p && _manual[i],
      ];
      _paths = [...playlist.paths];
      _index = playlist.index;
    }
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
    if (trackChanged) _rememberResume(_state.current, _lastPosition);
    _update(
      _state.copyWith(
        queue: queue,
        index: index,
        duration: trackChanged ? Duration.zero : null,
      ),
    );
    if (trackChanged) {
      _saveSession();
      if (current != null) _resumeIfSaved(current);
      // The track ended (or was skipped in the system controls): refill.
      unawaited(_topUp());
    }
  }

  // ------------------------------------------------------- long audio resume

  Map<String, int> _resumePositions() {
    final raw = _prefs.getString(_resumeKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, Object?>).map(
        (k, v) => MapEntry(k, (v! as num).toInt()),
      );
    } on Object {
      return {};
    }
  }

  /// Where [trackId] was left, if it is long audio started before.
  Duration? resumePositionOf(String trackId) =>
      switch (_resumePositions()[trackId]) {
        final int ms => Duration(milliseconds: ms),
        null => null,
      };

  void _rememberResume(LibraryTrack? track, Duration position) {
    if (track == null || !(isLong?.call(track) ?? false)) return;
    final positions = _resumePositions();
    final finished =
        track.durationMs > 0 &&
        position.inMilliseconds >= track.durationMs - 30000;
    if (finished) {
      positions.remove(track.id); // next time starts from the beginning
    } else if (position > const Duration(seconds: 10)) {
      positions
        ..remove(track.id)
        ..[track.id] = position.inMilliseconds; // re-added = newest
    } else {
      // Near the start (or the engine already reset the position while
      // switching tracks): keep whatever was saved.
      return;
    }
    while (positions.length > _maxResumeEntries) {
      positions.remove(positions.keys.first);
    }
    unawaited(_prefs.setString(_resumeKey, jsonEncode(positions)));
  }

  void _resumeIfSaved(LibraryTrack track) {
    if (!(isLong?.call(track) ?? false)) return;
    final saved = resumePositionOf(track.id);
    if (saved == null) return;
    // Seek once the file is loaded (its duration is known).
    unawaited(
      _backend.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5))
          .then((_) => _backend.seek(saved), onError: (Object _) {}),
    );
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
