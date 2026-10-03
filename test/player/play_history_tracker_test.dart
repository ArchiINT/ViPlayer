import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viplayer/core/library/library_models.dart';
import 'package:viplayer/core/player/audio_backend.dart';
import 'package:viplayer/core/player/play_history_tracker.dart';
import 'package:viplayer/core/player/player_service.dart';

import '../helpers/fake_audio_backend.dart';

LibraryTrack _track(String id, {int minutes = 3}) => LibraryTrack(
  id: id,
  title: id,
  artist: '',
  album: '',
  durationMs: minutes * 60000,
  liked: false,
  addedAt: 0,
  path: '/m/$id',
);

void main() {
  late FakeAudioBackend backend;
  late PlayerService player;
  late PlayHistoryTracker tracker;
  late List<String> played;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAudioBackend();
    player = PlayerService(backend, await SharedPreferences.getInstance());
    played = [];
    tracker = PlayHistoryTracker(player, (t, _) => played.add(t.id));
  });

  tearDown(() async {
    await tracker.dispose();
    await player.dispose();
  });

  /// Simulates listening in 1-second steps.
  void listen(int seconds, {int from = 0}) {
    for (var s = from + 1; s <= from + seconds; s++) {
      backend.advanceTo(Duration(seconds: s));
    }
  }

  test('counts a play after 30 seconds of listening, once', () async {
    await player.playQueue([_track('a')]);
    listen(29);
    expect(played, isEmpty);

    listen(40, from: 29);
    expect(played, ['a']);
  });

  test('short tracks count after half their length', () async {
    backend.fileDuration = const Duration(seconds: 20);
    await player.playQueue([_track('short', minutes: 0)]);
    listen(11);
    expect(played, ['short']);
  });

  test('seeking forward does not count as listening', () async {
    await player.playQueue([_track('a')]);
    listen(5);
    await player.seek(const Duration(minutes: 2));
    listen(5, from: 120);
    expect(played, isEmpty);
  });

  test('paused time does not count', () async {
    await player.playQueue([_track('a')]);
    await player.pause();
    listen(60);
    expect(played, isEmpty);
  });

  test(
    'skipping early records nothing; the next track counts itself',
    () async {
      await player.playQueue([_track('a'), _track('b')]);
      listen(10);
      await player.next();
      listen(31);
      expect(played, ['b']);
    },
  );

  test('repeat one counts every pass', () async {
    await player.playQueue([_track('a')]);
    await backend.setRepeat(PlaybackRepeat.one);
    listen(40);
    // The engine loops back to the start of the same track.
    backend.advanceTo(Duration.zero);
    listen(40);
    expect(played, ['a', 'a']);
  });
}
