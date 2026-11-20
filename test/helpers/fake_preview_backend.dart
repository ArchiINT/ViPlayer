import 'dart:async';

import 'package:viplayer/core/download/download_models.dart';
import 'package:viplayer/core/player/preview_player.dart';

/// In-memory [PreviewBackend]: "plays" instantly, records opened URLs.
class FakePreviewBackend implements PreviewBackend {
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration>.broadcast(sync: true);
  final _completed = StreamController<bool>.broadcast(sync: true);
  final opened = <String>[];
  final seeks = <Duration>[];

  /// When false, [open] succeeds but no sound starts (position stays 0).
  bool startsPlaying = true;

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
    opened.add(stream.url);
    _duration.add(const Duration(minutes: 3));
    _playing.add(true);
    if (startsPlaying) _position.add(const Duration(milliseconds: 50));
  }

  @override
  Future<void> play() async => _playing.add(true);
  @override
  Future<void> pause() async => _playing.add(false);
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _position.add(position);
  }

  @override
  Future<void> stop() async => _playing.add(false);
  @override
  Future<void> dispose() async {}

  void finish() => _completed.add(true);
}
