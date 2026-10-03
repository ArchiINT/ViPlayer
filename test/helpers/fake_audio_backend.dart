import 'dart:async';

import 'package:viplayer/core/player/audio_backend.dart';

/// In-memory [AudioBackend] that mimics mpv's playlist behaviour, so player
/// logic can be tested without an audio device. Streams are synchronous:
/// state is visible right after each call.
class FakeAudioBackend implements AudioBackend {
  final _playlist = StreamController<BackendPlaylist>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration>.broadcast(sync: true);
  final _shuffle = StreamController<bool>.broadcast(sync: true);
  final _repeat = StreamController<PlaybackRepeat>.broadcast(sync: true);
  final _volume = StreamController<double>.broadcast(sync: true);

  List<String> paths = [];
  int index = -1;
  bool isPlaying = false;
  bool isShuffled = false;
  PlaybackRepeat repeatMode = PlaybackRepeat.off;
  Duration positionValue = Duration.zero;
  double volumeValue = 100;

  /// Every method call, for asserting what the player asked for.
  final calls = <String>[];

  /// Length reported for every opened file.
  Duration fileDuration = const Duration(minutes: 3);

  void _emitPlaylist() =>
      _playlist.add(BackendPlaylist(List.unmodifiable(paths), index));

  void _load() {
    positionValue = Duration.zero;
    _position.add(Duration.zero);
    _duration.add(index < 0 ? Duration.zero : fileDuration);
  }

  /// Test hook: pretend playback reached [position].
  void advanceTo(Duration position) {
    positionValue = position;
    _position.add(position);
  }

  @override
  Stream<BackendPlaylist> get playlist => _playlist.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<bool> get shuffle => _shuffle.stream;
  @override
  Stream<PlaybackRepeat> get repeat => _repeat.stream;
  @override
  Stream<double> get volume => _volume.stream;
  @override
  Duration get currentPosition => positionValue;

  @override
  Future<void> open(
    List<String> paths, {
    int index = 0,
    bool play = true,
  }) async {
    calls.add('open($index, play: $play)');
    this.paths = [...paths];
    this.index = index;
    _emitPlaylist();
    _load();
    isPlaying = play;
    _playing.add(play);
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> playOrPause() => isPlaying ? pause() : play();

  @override
  Future<void> next() async {
    calls.add('next');
    if (index < paths.length - 1) {
      index++;
    } else if (repeatMode == PlaybackRepeat.all) {
      index = 0;
    } else {
      return;
    }
    _emitPlaylist();
    _load();
  }

  @override
  Future<void> previous() async {
    calls.add('previous');
    if (index > 0) index--;
    _emitPlaylist();
    _load();
  }

  @override
  Future<void> jump(int index) async {
    calls.add('jump($index)');
    this.index = index;
    _emitPlaylist();
    _load();
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek(${position.inSeconds}s)');
    advanceTo(position);
  }

  @override
  Future<void> add(String path) async {
    paths.add(path);
    _emitPlaylist();
  }

  @override
  Future<void> remove(int index) async {
    paths.removeAt(index);
    if (index < this.index) this.index--;
    _emitPlaylist();
  }

  @override
  Future<void> move(int from, int to) async {
    // mpv: the entry at [from] takes the place of the entry at [to].
    final current = paths[index];
    final item = paths.removeAt(from);
    paths.insert(from < to ? to - 1 : to, item);
    index = paths.indexOf(current);
    _emitPlaylist();
  }

  @override
  Future<void> setShuffle(bool shuffle) async {
    isShuffled = shuffle;
    if (shuffle && paths.isNotEmpty) {
      // Deterministic "shuffle": current first, the rest reversed.
      final current = paths[index];
      final rest = [...paths]..remove(current);
      paths = [current, ...rest.reversed];
      index = 0;
      _emitPlaylist();
    }
    _shuffle.add(shuffle);
  }

  @override
  Future<void> setRepeat(PlaybackRepeat mode) async {
    repeatMode = mode;
    _repeat.add(mode);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeValue = volume;
    _volume.add(volume);
  }

  @override
  Future<void> stop() async {
    paths = [];
    index = -1;
    _emitPlaylist();
  }

  @override
  Future<void> dispose() async {}
}
