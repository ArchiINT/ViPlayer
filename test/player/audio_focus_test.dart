import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viplayer/core/library/library_models.dart';
import 'package:viplayer/core/player/audio_focus.dart';
import 'package:viplayer/core/player/player_service.dart';

import '../helpers/fake_audio_backend.dart';

void main() {
  late FakeAudioBackend backend;
  late PlayerService player;
  late AudioFocus focus;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAudioBackend();
    player = PlayerService(backend, await SharedPreferences.getInstance());
    focus = AudioFocus(player);
    await player.playQueue([
      const LibraryTrack(
        id: 'a',
        title: 'a',
        artist: '',
        album: '',
        durationMs: 1000,
        liked: false,
        addedAt: 0,
        path: '/a',
      ),
    ]);
  });
  tearDown(() => player.dispose());

  test('a call pauses, and playback resumes after it', () {
    focus.handleInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    expect(backend.isPlaying, isFalse);
    focus.handleInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    expect(backend.isPlaying, isTrue);
  });

  test('music paused by the user stays paused after a call', () async {
    await player.pause();
    focus.handleInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    focus.handleInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    expect(backend.isPlaying, isFalse);
  });

  test('short sounds duck the volume, then restore it', () async {
    await player.setVolume(80);
    focus.handleInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.duck),
    );
    expect(backend.volumeValue, closeTo(24, 0.01));
    focus.handleInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.duck),
    );
    expect(backend.volumeValue, 80);
    expect(backend.isPlaying, isTrue);
  });

  test('unplugging headphones pauses', () {
    focus.handleBecomingNoisy();
    expect(backend.isPlaying, isFalse);
  });
}
