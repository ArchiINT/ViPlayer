import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

enum PlaybackRepeat { off, all, one }

/// The playlist as the engine plays it: file paths in play order (shuffled
/// if shuffle is on) and the index of the current one.
class BackendPlaylist {
  const BackendPlaylist(this.paths, this.index);

  final List<String> paths;
  final int index;
}

/// The audio engine, reduced to what the player needs. Lets PlayerService be
/// tested with a fake instead of a real audio device.
abstract interface class AudioBackend {
  Stream<BackendPlaylist> get playlist;
  Stream<bool> get playing;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get shuffle;
  Stream<PlaybackRepeat> get repeat;

  /// 0..100
  Stream<double> get volume;

  Duration get currentPosition;

  Future<void> open(List<String> paths, {int index = 0, bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> next();
  Future<void> previous();
  Future<void> jump(int index);
  Future<void> seek(Duration position);

  /// Appends to the end of the playlist.
  Future<void> add(String path);
  Future<void> remove(int index);

  /// mpv semantics: the entry at [from] takes the place of the entry at [to]
  /// (it ends up *before* the entry that was at [to]).
  Future<void> move(int from, int to);
  Future<void> setShuffle(bool shuffle);
  Future<void> setRepeat(PlaybackRepeat mode);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

/// [AudioBackend] on media_kit (libmpv): gapless playback, every common
/// format, same engine on Linux and Android.
class MediaKitBackend implements AudioBackend {
  MediaKitBackend()
    : _player = mk.Player(
        configuration: const mk.PlayerConfiguration(
          title: 'ViPlayer',
          // Music only: never decode video streams (e.g. embedded art).
          vo: 'null',
          bufferSize: 8 * 1024 * 1024,
        ),
      );

  final mk.Player _player;

  static void ensureInitialized() => mk.MediaKit.ensureInitialized();

  @override
  Stream<BackendPlaylist> get playlist => _player.stream.playlist.map(
    (p) => BackendPlaylist([for (final m in p.medias) _pathOf(m.uri)], p.index),
  );

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<bool> get shuffle => _player.stream.shuffle;

  @override
  Stream<PlaybackRepeat> get repeat => _player.stream.playlistMode.map(
    (m) => switch (m) {
      mk.PlaylistMode.none => PlaybackRepeat.off,
      mk.PlaylistMode.loop => PlaybackRepeat.all,
      mk.PlaylistMode.single => PlaybackRepeat.one,
    },
  );

  @override
  Stream<double> get volume => _player.stream.volume;

  @override
  Duration get currentPosition => _player.state.position;

  @override
  Future<void> open(List<String> paths, {int index = 0, bool play = true}) =>
      _player.open(
        mk.Playlist([for (final p in paths) mk.Media(p)], index: index),
        play: play,
      );

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> next() => _player.next();

  @override
  Future<void> previous() => _player.previous();

  @override
  Future<void> jump(int index) => _player.jump(index);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> add(String path) => _player.add(mk.Media(path));

  @override
  Future<void> remove(int index) => _player.remove(index);

  @override
  Future<void> move(int from, int to) => _player.move(from, to);

  @override
  Future<void> setShuffle(bool shuffle) => _player.setShuffle(shuffle);

  @override
  Future<void> setRepeat(PlaybackRepeat mode) =>
      _player.setPlaylistMode(switch (mode) {
        PlaybackRepeat.off => mk.PlaylistMode.none,
        PlaybackRepeat.all => mk.PlaylistMode.loop,
        PlaybackRepeat.one => mk.PlaylistMode.single,
      });

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();

  /// media_kit may hand local files back as `file://` URIs.
  static String _pathOf(String uri) =>
      uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
}
