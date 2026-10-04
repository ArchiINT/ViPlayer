import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viplayer/core/library/library_models.dart';
import 'package:viplayer/core/player/audio_backend.dart';
import 'package:viplayer/core/player/player_service.dart';

import '../helpers/fake_audio_backend.dart';

LibraryTrack _track(String id, {int durationMs = 180000}) => LibraryTrack(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  album: 'Album',
  durationMs: durationMs,
  liked: false,
  addedAt: 0,
  path: '/music/$id.m4a',
);

void main() {
  late FakeAudioBackend backend;
  late SharedPreferences prefs;
  late PlayerService player;
  final tracks = [
    for (final id in ['a', 'b', 'c', 'd']) _track(id),
  ];

  Future<PlayerService> newPlayer() async {
    final p = PlayerService(backend, prefs);
    addTearDown(p.dispose);
    return p;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backend = FakeAudioBackend();
    player = await newPlayer();
  });

  PlayerSnapshot state() => player.snapshot.value;
  List<String> queueIds() => [for (final t in state().queue) t.id];

  test('playQueue starts the chosen track', () async {
    await player.playQueue(tracks, startIndex: 2);

    expect(state().current!.id, 'c');
    expect(state().playing, isTrue);
    expect(queueIds(), ['a', 'b', 'c', 'd']);
  });

  test('previous restarts the track after 3 seconds, else goes back', () async {
    await player.playQueue(tracks, startIndex: 1);

    backend.advanceTo(const Duration(seconds: 10));
    await player.previous();
    expect(state().current!.id, 'b');
    expect(backend.positionValue, Duration.zero);

    backend.advanceTo(const Duration(seconds: 1));
    await player.previous();
    expect(state().current!.id, 'a');
  });

  test('playNext inserts right after the current track', () async {
    await player.playQueue(tracks, startIndex: 1);
    await player.playNext(_track('x'));

    expect(queueIds(), ['a', 'b', 'x', 'c', 'd']);
    expect(state().current!.id, 'b');
  });

  test('addToQueue appends; works on an empty player too', () async {
    await player.addToQueue(_track('x'));
    expect(state().current!.id, 'x');

    await player.addToQueue(_track('y'));
    expect(queueIds(), ['x', 'y']);
  });

  test('the same song queued twice keeps the right current index', () async {
    await player.playQueue([tracks[0], tracks[1], tracks[0]], startIndex: 2);

    expect(state().index, 2);
  });

  test('reorder and remove keep the current track playing', () async {
    await player.playQueue(tracks, startIndex: 1);

    await player.reorder(3, 0); // d to the top
    expect(queueIds(), ['d', 'a', 'b', 'c']);
    expect(state().current!.id, 'b');

    await player.reorder(1, 3); // a to the bottom
    expect(queueIds(), ['d', 'b', 'c', 'a']);
    expect(state().current!.id, 'b');

    await player.removeAt(0);
    expect(queueIds(), ['b', 'c', 'a']);
    expect(state().current!.id, 'b');
  });

  test('repeat cycles off -> all -> one -> off', () async {
    expect(state().repeat, PlaybackRepeat.off);
    await player.cycleRepeat();
    expect(state().repeat, PlaybackRepeat.all);
    await player.cycleRepeat();
    expect(state().repeat, PlaybackRepeat.one);
    await player.cycleRepeat();
    expect(state().repeat, PlaybackRepeat.off);
  });

  test('a new queue starts in order even with shuffle on', () async {
    await player.playQueue(tracks);
    await player.toggleShuffle();
    expect(state().shuffle, isTrue);

    await player.playQueue(tracks, startIndex: 2);

    expect(state().current!.id, 'c', reason: 'the tapped track plays');
    expect(state().shuffle, isTrue);
  });

  test('reports durations that differ from the tags', () async {
    final measured = <String>[];
    player.onDurationMeasured = (t, d) =>
        measured.add('${t.id}:${d.inSeconds}');
    backend.fileDuration = const Duration(minutes: 3); // matches tags

    await player.playQueue([_track('ok'), _track('off', durationMs: 60000)]);
    await player.next();

    expect(measured, ['off:180']);
  });

  test('session is restored on the next start without auto-play', () async {
    await player.playQueue(tracks, startIndex: 2);
    await player.cycleRepeat();
    await player.setVolume(40);
    backend.advanceTo(const Duration(seconds: 42));
    await player.dispose(); // saves the session

    backend = FakeAudioBackend();
    final restored = PlayerService(backend, prefs);
    addTearDown(restored.dispose);
    await restored.restoreSession({for (final t in tracks) t.path: t});

    final s = restored.snapshot.value;
    expect(s.current!.id, 'c');
    expect(s.playing, isFalse);
    expect(s.repeat, PlaybackRepeat.all);
    expect(s.volume, 40);
    expect(backend.positionValue, const Duration(seconds: 42));
  });

  test('restore skips tracks that left the library', () async {
    await player.playQueue(tracks, startIndex: 1);
    await player.dispose();

    backend = FakeAudioBackend();
    final restored = PlayerService(backend, prefs);
    addTearDown(restored.dispose);
    // 'b' (the current one) and 'c' are gone.
    await restored.restoreSession({
      for (final t in tracks)
        if (t.id != 'b' && t.id != 'c') t.path: t,
    });

    final s = restored.snapshot.value;
    expect([for (final t in s.queue) t.id], ['a', 'd']);
    expect(s.current!.id, 'a');
    expect(backend.positionValue, Duration.zero);
  });

  group('long audio resumes where it was left', () {
    final book = _track('book', durationMs: 3 * 3600 * 1000);
    final song = _track('song');

    setUp(() => player.isLong = (t) => t.durationMs > 20 * 60000);

    test('switching away and back continues the book', () async {
      await player.playQueue([book, song]);
      backend.advanceTo(const Duration(minutes: 42));
      await player.next(); // to the song
      expect(player.resumePositionOf('book'), const Duration(minutes: 42));

      await player.previous(); // song just started: goes back to the book
      expect(state().current!.id, 'book');
      expect(backend.positionValue, const Duration(minutes: 42));
    });

    test('a position reset while switching does not erase the mark', () async {
      await player.playQueue([book, song]);
      backend.advanceTo(const Duration(minutes: 42));
      await player.next();
      backend.advanceTo(Duration.zero);
      await player.jumpTo(0);
      expect(player.resumePositionOf('book'), const Duration(minutes: 42));
    });

    test('a finished book starts over next time', () async {
      await player.playQueue([book, song]);
      backend.advanceTo(Duration(milliseconds: book.durationMs - 5000));
      await player.next();
      expect(player.resumePositionOf('book'), isNull);
    });

    test('songs do not resume', () async {
      await player.playQueue([song, book]);
      backend.advanceTo(const Duration(minutes: 2));
      await player.next();
      expect(player.resumePositionOf('song'), isNull);
    });
  });
}
