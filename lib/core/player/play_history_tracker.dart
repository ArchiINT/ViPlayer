import 'dart:async';
import 'dart:math' as math;

import '../library/library_models.dart';
import 'player_service.dart';

/// Decides when a track counts as "played" for the history: after
/// [minListen] of actual listening, or half the track if it is shorter.
///
/// Only real listening counts — position jumps from seeking are ignored —
/// and each start of a track is counted at most once (a repeat-one loop
/// counts again on every pass).
class PlayHistoryTracker {
  PlayHistoryTracker(this._player, this._record) {
    _player.snapshot.addListener(_onSnapshot);
    _positionSub = _player.position.listen(_onPosition);
    _onSnapshot();
  }

  static const minListen = Duration(seconds: 30);

  /// Position steps larger than this are seeks, not listening.
  static const _maxStep = Duration(seconds: 2);

  final PlayerService _player;
  final void Function(LibraryTrack track, Duration listened) _record;
  late final StreamSubscription<Duration> _positionSub;

  String? _key; // identifies one start of one track
  Duration _listened = Duration.zero;
  Duration? _lastPosition;
  bool _recorded = false;

  void _onSnapshot() {
    final s = _player.snapshot.value;
    final key = s.current == null ? null : '${s.index}:${s.current!.id}';
    if (key != _key) _restart(key);
  }

  void _restart(String? key) {
    _key = key;
    _listened = Duration.zero;
    _lastPosition = null;
    _recorded = false;
  }

  void _onPosition(Duration position) {
    final s = _player.snapshot.value;
    final track = s.current;
    if (track == null) return;

    final last = _lastPosition;
    _lastPosition = position;
    if (last == null) return;

    // Jumped back to the start after counting: the track is playing again
    // (repeat one, or "previous" restarting it).
    if (_recorded && position < _maxStep && last - position > _maxStep) {
      _restart(_key);
      _lastPosition = position;
      return;
    }

    final step = position - last;
    if (!s.playing || step <= Duration.zero || step > _maxStep) return;
    _listened += step;

    if (!_recorded && _listened >= _threshold(track, s.duration)) {
      _recorded = true;
      _record(track, _listened);
    }
  }

  Duration _threshold(LibraryTrack track, Duration measured) {
    final length = measured > Duration.zero
        ? measured
        : Duration(milliseconds: track.durationMs);
    if (length <= Duration.zero) return minListen;
    return Duration(
      milliseconds: math.min(
        minListen.inMilliseconds,
        length.inMilliseconds ~/ 2,
      ),
    );
  }

  Future<void> dispose() async {
    _player.snapshot.removeListener(_onSnapshot);
    await _positionSub.cancel();
  }
}
