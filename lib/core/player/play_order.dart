import 'dart:math' as math;

/// Where the automatic part of the queue comes from: the list playback was
/// started from (library, playlist, liked tracks), dealt in order or
/// shuffled, round after round — so "up next" never runs dry.
///
/// In order it wraps around after the last track. Shuffled it deals like a
/// deck of cards: every track once per round, a fresh shuffle for the next
/// round, never the same track twice in a row (unless it is the only one).
///
/// Works on file paths, like the engine; the player maps them to tracks.
class PlayOrder {
  /// [start] is the track that plays first: dealing continues after it.
  PlayOrder(
    List<String> paths, {
    required bool shuffle,
    int start = 0,
    math.Random? random,
  }) : _paths = [...paths],
       _shuffle = shuffle,
       _random = random ?? math.Random() {
    if (_paths.isEmpty) return;
    final first = start.clamp(0, _paths.length - 1);
    _last = _paths[first];
    if (shuffle) {
      _bag = _newRound(without: first);
    } else {
      _cursor = (first + 1) % _paths.length;
    }
  }

  PlayOrder._restored(
    this._paths,
    this._shuffle,
    this._cursor,
    this._bag,
    this._last,
  ) : _random = math.Random();

  final List<String> _paths;
  final math.Random _random;
  bool _shuffle;

  /// In order: index of the next path to deal.
  int _cursor = 0;

  /// Shuffled: what is left of this round; the next path is the last one.
  List<String> _bag = [];

  /// The path dealt (or started) most recently.
  String? _last;

  List<String> get paths => List.unmodifiable(_paths);
  bool get shuffle => _shuffle;

  /// The next [count] paths. Empty only when the list is empty.
  List<String> take(int count) {
    if (_paths.isEmpty) return const [];
    return [for (var i = 0; i < count; i++) _deal()];
  }

  String _deal() {
    final String path;
    if (_shuffle) {
      if (_bag.isEmpty) _bag = _newRound();
      path = _bag.removeLast();
    } else {
      _cursor %= _paths.length;
      path = _paths[_cursor];
      _cursor = (_cursor + 1) % _paths.length;
    }
    _last = path;
    return path;
  }

  /// A shuffled round of every path (minus the one at [without]); the one
  /// dealt first is never [_last] when there is a choice.
  List<String> _newRound({int? without}) {
    final round = [
      for (final (i, p) in _paths.indexed)
        if (i != without) p,
    ]..shuffle(_random);
    if (round.length > 1 && round.last == _last) {
      final other = round.lastIndexWhere((p) => p != _last);
      if (other >= 0) {
        round[round.length - 1] = round[other];
        round[other] = _last!;
      }
    }
    return round;
  }

  /// Switches mode; dealing continues after [current] (the playing track).
  void setShuffle(bool shuffle, {String? current}) {
    _shuffle = shuffle;
    if (_paths.isEmpty) return;
    final at = current == null ? -1 : _paths.indexOf(current);
    _last = current ?? _last;
    if (shuffle) {
      _bag = _newRound(without: at < 0 ? null : at);
    } else {
      _cursor = at < 0 ? 0 : (at + 1) % _paths.length;
    }
  }

  /// Forgets [path] (its file was deleted).
  void remove(String path) {
    for (var i = _paths.length - 1; i >= 0; i--) {
      if (_paths[i] != path) continue;
      _paths.removeAt(i);
      if (i < _cursor) _cursor--;
    }
    _bag.removeWhere((p) => p == path);
    if (_paths.isNotEmpty) _cursor %= _paths.length;
  }

  Map<String, Object?> toJson() => {
    'paths': _paths,
    'shuffle': _shuffle,
    'cursor': _cursor,
    'bag': _bag,
    'last': _last,
  };

  /// Restores a saved order, keeping only paths for which [known] is true
  /// (tracks deleted meanwhile are dropped). Null when nothing is left.
  static PlayOrder? fromJson(
    Map<String, Object?> json,
    bool Function(String path) known,
  ) {
    final saved = (json['paths'] as List<Object?>? ?? const []).cast<String>();
    final paths = [
      for (final p in saved)
        if (known(p)) p,
    ];
    if (paths.isEmpty) return null;
    // The cursor counted the saved list: shift it past dropped paths.
    final savedCursor = (json['cursor'] as num?)?.toInt() ?? 0;
    final dropped = saved
        .take(savedCursor.clamp(0, saved.length))
        .where((p) => !known(p))
        .length;
    return PlayOrder._restored(
      paths,
      json['shuffle'] == true,
      (savedCursor - dropped).clamp(0, paths.length - 1),
      [
        for (final p
            in (json['bag'] as List<Object?>? ?? const []).cast<String>())
          if (known(p)) p,
      ],
      json['last'] as String?,
    );
  }
}
