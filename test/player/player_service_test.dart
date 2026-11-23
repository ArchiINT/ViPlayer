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
  List<String> head(int n) => queueIds().take(n).toList();
  List<String> upNext() => queueIds().sublist(state().index + 1);

  test('playQueue starts the chosen track, up next is 20 in order', () async {
    await player.playQueue(tracks, startIndex: 2);

    expect(state().current!.id, 'c');
    expect(state().playing, isTrue);
    expect(head(4), ['a', 'b', 'c', 'd'], reason: 'earlier tracks behind');
    expect(upNext(), hasLength(PlayerService.upNextTarget));
    // The list goes round: d, then from the start again.
    expect(upNext().take(5), ['d', 'a', 'b', 'c', 'd']);
  });

  test('up next stays at 20 as tracks play and are removed', () async {
    await player.playQueue(tracks);
    for (var i = 0; i < 30; i++) {
      await player.next();
      expect(upNext(), hasLength(PlayerService.upNextTarget));
    }

    final last = upNext().last;
    await player.removeAt(state().index + 1);
    expect(upNext(), hasLength(PlayerService.upNextTarget));
    expect(upNext()[upNext().length - 2], last, reason: 'refilled at the end');
  });

  test('added tracks come on top of the 20, then it shrinks back', () async {
    await player.playQueue(tracks);
    await player.addToQueue(_track('x'));
    await player.playNext(_track('y'));
    expect(upNext(), hasLength(22));
    expect(upNext().first, 'y');
    expect(upNext().last, 'x');

    await player.next(); // y
    expect(upNext(), hasLength(21));
    await player.next();
    expect(upNext(), hasLength(20));
    await player.next();
    expect(upNext(), hasLength(20));
  });

  test('old history is dropped, recent history kept for previous', () async {
    await player.playQueue(tracks);
    for (var i = 0; i < 80; i++) {
      await player.next();
    }
    expect(state().index, PlayerService.historyKept);
    expect(queueIds(), hasLength(PlayerService.historyKept + 1 + 20));
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

    expect(head(5), ['a', 'b', 'x', 'c', 'd']);
    expect(state().current!.id, 'b');
  });

  test('a track queued while nothing plays just plays', () async {
    await player.addToQueue(_track('x'));
    expect(state().current!.id, 'x');

    await player.addToQueue(_track('y'));
    expect(queueIds(), ['x', 'y'], reason: 'no list to continue from');
  });

  test('the same song queued twice keeps the right current index', () async {
    await player.playQueue([tracks[0], tracks[1], tracks[0]], startIndex: 2);

    expect(state().index, 2);
  });

  test('reorder and remove keep the current track playing', () async {
    await player.playQueue(tracks, startIndex: 1);

    await player.reorder(3, 0); // d to the top
    expect(head(4), ['d', 'a', 'b', 'c']);
    expect(state().current!.id, 'b');

    await player.reorder(1, 3); // a after c
    expect(head(4), ['d', 'b', 'c', 'a']);
    expect(state().current!.id, 'b');

    await player.removeAt(0);
    expect(head(3), ['b', 'c', 'a']);
    expect(state().current!.id, 'b');
  });

  test('repeat cycles off -> one -> off', () async {
    expect(state().repeat, PlaybackRepeat.off);
    await player.cycleRepeat();
    expect(state().repeat, PlaybackRepeat.one);
    await player.cycleRepeat();
    expect(state().repeat, PlaybackRepeat.off);
  });

  group('shuffle', () {
    final many = [for (var i = 0; i < 30; i++) _track('t$i')];

    test('the tapped track plays, then every track once per round', () async {
      await player.toggleShuffle();
      await player.playQueue(many, startIndex: 5);

      expect(state().current!.id, 't5');
      expect(state().shuffle, isTrue);
      expect(state().index, 0, reason: 'no history before a shuffled start');
      final next20 = upNext();
      expect(next20, hasLength(20));
      expect(next20.toSet(), hasLength(20), reason: 'no repeats in a round');
      expect(next20, isNot(contains('t5')));
    });

    test('never runs out, never repeats a track back to back', () async {
      final three = many.take(3).toList();
      await player.shufflePlay(three);
      final played = <String>[state().current!.id];
      for (var i = 0; i < 40; i++) {
        expect(upNext(), hasLength(20));
        await player.next();
        played.add(state().current!.id);
      }
      for (var i = 1; i < played.length; i++) {
        expect(played[i], isNot(played[i - 1]));
      }
      // The first round deals the two not started with; then rounds of 3.
      expect(played.sublist(1, 3).toSet(), hasLength(2));
      for (var r = 3; r + 3 <= played.length; r += 3) {
        expect(played.sublist(r, r + 3).toSet(), hasLength(3));
      }
    });

    test('toggling rebuilds the automatic part, keeps added tracks', () async {
      await player.playQueue(many);
      await player.playNext(_track('mine'));

      await player.toggleShuffle();
      expect(upNext().first, 'mine');
      // Refilled to 20 in all, the added track included.
      expect(upNext(), hasLength(20));
      expect(upNext().skip(1).toSet(), hasLength(19));

      await player.toggleShuffle(); // back in order, after the current track
      expect(upNext().take(3), ['mine', 't1', 't2']);
    });
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
    await player.playNext(_track('x'));
    backend.advanceTo(const Duration(seconds: 42));
    await player.dispose(); // saves the session

    backend = FakeAudioBackend();
    final restored = PlayerService(backend, prefs);
    addTearDown(restored.dispose);
    await restored.restoreSession({
      for (final t in [...tracks, _track('x')]) t.path: t,
    });

    final s = restored.snapshot.value;
    expect(s.current!.id, 'c');
    expect(s.playing, isFalse);
    expect(s.repeat, PlaybackRepeat.one);
    expect(s.volume, 40);
    expect(backend.positionValue, const Duration(seconds: 42));
    final next = [for (final t in s.queue.sublist(s.index + 1)) t.id];
    expect(next.take(3), ['x', 'd', 'a']);
    expect(next, hasLength(21));
  });

  test('shuffle and its order survive a restart', () async {
    final many = [for (var i = 0; i < 30; i++) _track('t$i')];
    await player.shufflePlay(many);
    final before = upNext();
    await player.dispose();

    backend = FakeAudioBackend();
    final restored = PlayerService(backend, prefs);
    addTearDown(restored.dispose);
    await restored.restoreSession({for (final t in many) t.path: t});

    final s = restored.snapshot.value;
    expect(s.shuffle, isTrue);
    expect([for (final t in s.queue.sublist(s.index + 1)) t.id], before);
    await restored.next();
    expect(
      restored.snapshot.value.queue.length - 1 - restored.snapshot.value.index,
      20,
    );
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
    expect(s.current!.id, 'a');
    expect({for (final t in s.queue) t.id}, {'a', 'd'});
    expect(s.queue.length - 1 - s.index, greaterThanOrEqualTo(20));
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
