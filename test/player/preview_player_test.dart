import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/download/download_models.dart';
import 'package:viplayer/core/player/preview_player.dart';

import '../helpers/fake_preview_backend.dart';

DownloadCandidate _c(String id) => DownloadCandidate(
  service: MusicService.soundcloud,
  sourceId: id,
  sourceUrl: 'https://soundcloud.com/x/$id',
  title: id,
  artist: 'a',
  durationMs: 180000,
);

void main() {
  late FakePreviewBackend backend;
  late PreviewPlayer preview;
  late int mainPaused;

  setUp(() {
    backend = FakePreviewBackend();
    preview = PreviewPlayer(backend);
    mainPaused = 0;
    preview.onStart = () => mainPaused++;
  });
  tearDown(() => preview.dispose());

  Future<PreviewStream> url(String u) async => PreviewStream(u);

  test('plays, pauses and resumes the same result', () async {
    await preview.toggle(_c('a'), () => url('A'));
    expect(preview.state.value.playing, isTrue);
    expect(preview.state.value.key, 'soundcloud:a');
    expect(mainPaused, 1, reason: 'main player paused');

    await preview.toggle(_c('a'), () => url('A'));
    expect(preview.state.value.playing, isFalse);
    await preview.toggle(_c('a'), () => url('A'));
    expect(preview.state.value.playing, isTrue);
    expect(backend.opened, ['A'], reason: 'not re-resolved');
  });

  test('another result replaces the current one', () async {
    await preview.toggle(_c('a'), () => url('A'));
    await preview.toggle(_c('b'), () => url('B'));
    expect(preview.state.value.key, 'soundcloud:b');
    expect(backend.opened, ['A', 'B']);
  });

  test('a slow resolve is dropped if the user moved on', () async {
    final slow = Completer<PreviewStream>();
    final first = preview.toggle(_c('a'), () => slow.future);
    expect(preview.state.value.loading, isTrue);

    await preview.toggle(_c('b'), () => url('B'));
    slow.complete(const PreviewStream('A'));
    await first;

    expect(preview.state.value.key, 'soundcloud:b');
    expect(backend.opened, ['B']);
  });

  test('failures are shown and can be retried', () async {
    await preview.toggle(
      _c('a'),
      () async => throw const DownloadException(DownloadFailure.network),
    );
    expect(preview.state.value.failure, DownloadFailure.network);

    await preview.toggle(_c('a'), () => url('A'));
    expect(preview.state.value.failure, isNull);
    expect(preview.state.value.playing, isTrue);
  });

  test('stops at the end of the track and on stop()', () async {
    await preview.toggle(_c('a'), () => url('A'));
    backend.finish();
    expect(preview.state.value.key, isNull);

    await preview.toggle(_c('b'), () => url('B'));
    await preview.stop();
    expect(preview.state.value.key, isNull);
  });

  test('stays loading until sound starts, fails if it never does', () async {
    backend.startsPlaying = false;
    final slow = PreviewPlayer(
      backend,
      startTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(slow.dispose);

    await slow.toggle(_c('a'), () => url('A'));
    expect(slow.state.value.loading, isTrue, reason: 'opened, but silent');

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(slow.state.value.loading, isFalse);
    expect(slow.state.value.failure, DownloadFailure.network);
  });

  test('seeks within the playing preview, not while loading', () async {
    await preview.toggle(_c('a'), () => url('A'));
    await preview.seek(const Duration(seconds: 90));
    expect(backend.seeks, [const Duration(seconds: 90)]);
    expect(preview.state.value.position, const Duration(seconds: 90));

    backend.startsPlaying = false;
    await preview.toggle(_c('b'), () => url('B'));
    await preview.seek(const Duration(seconds: 10));
    expect(backend.seeks, hasLength(1));
  });

  test('split backend: HLS to one engine, the rest to the other', () async {
    final main = FakePreviewBackend();
    final hls = FakePreviewBackend();
    final split = PreviewPlayer(SplitPreviewBackend(main, hls));
    addTearDown(split.dispose);

    await split.toggle(
      _c('a'),
      () async => const PreviewStream('A.m3u8', hls: true),
    );
    await split.toggle(_c('b'), () => url('B.mp3'));
    expect(hls.opened, ['A.m3u8']);
    expect(main.opened, ['B.mp3']);
    expect(split.state.value.playing, isTrue);

    // Events of the engine not in use are ignored.
    hls.finish();
    expect(split.state.value.key, 'soundcloud:b');
  });
}
