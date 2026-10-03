@Tags(['online'])
library;

import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:viplayer/core/database/app_database.dart';
import 'package:viplayer/core/download/download_models.dart';
import 'package:viplayer/core/download/download_service.dart';
import 'package:viplayer/core/download/tools/tagger.dart';
import 'package:viplayer/core/download/tools/ytdlp.dart';
import 'package:viplayer/core/library/cover_store.dart';
import 'package:viplayer/core/library/library_repository.dart';
import 'package:viplayer/core/library/library_scanner.dart';

/// The full desktop pipeline against real services (yt-dlp + ffmpeg), with
/// free-to-use NCS releases: link -> file with tags and cover -> library.
void main() {
  late Directory temp;
  late AppDatabase db;
  late DownloadService service;
  late LibraryRepository library;
  final client = http.Client();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vp_pipe_');
    db = AppDatabase(NativeDatabase.memory());
    final covers = p.join(temp.path, 'covers');
    await Directory(covers).create();
    library = LibraryRepository(db, CoverStore(covers));
    final scanner = LibraryScanner(
      db,
      coversDir: covers,
      downloadDir: p.join(temp.path, 'music'),
    );
    service = DownloadService(
      client: client,
      downloadDirectory: p.join(temp.path, 'music'),
      library: library,
      importFile: scanner.importFile,
      tagger: const FfmpegTagger(),
      ytdlp: YtDlp(binDirectory: p.join(temp.path, 'bin')),
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  tearDownAll(client.close);

  Future<void> check(String link, {String ext = 'm4a'}) async {
    final resolved = await service.resolve(link);
    final stages = <DownloadStage>{};
    await service.download(
      resolved.items.single,
      format: DownloadFormat.values.byName(ext),
      onProgress: (stage, _) => stages.add(stage),
    );

    final tracks = await library.watchTracks().first;
    final track = tracks.single;
    expect(p.extension(track.path), '.$ext');
    expect(track.path, startsWith(p.join(temp.path, 'music')));
    expect(track.coverPath, isNotNull, reason: 'cover embedded and read');
    final tags = readMetadata(File(track.path));
    expect(tags.title, resolved.items.single.title);
    expect(
      stages,
      containsAll(
        DownloadStage.values.where((s) => s != DownloadStage.matching),
      ),
    );

    // Second time: recognised as already downloaded.
    await expectLater(
      service.download(resolved.items.single, format: DownloadFormat.m4a),
      throwsA(
        isA<DownloadException>().having(
          (e) => e.reason,
          'reason',
          DownloadFailure.alreadyInLibrary,
        ),
      ),
    );
  }

  const timeout = Timeout(Duration(minutes: 3));

  test(
    'YouTube via yt-dlp (m4a)',
    () => check('https://youtu.be/vg95MYlTb3c'),
    timeout: timeout,
  );

  test(
    'YouTube via yt-dlp (opus)',
    () => check('https://youtu.be/vg95MYlTb3c', ext: 'opus'),
    timeout: timeout,
  );

  test(
    'SoundCloud via yt-dlp',
    () => check(
      'https://soundcloud.com/nocopyrightsounds/angelrot-backtoback-ncs',
    ),
    timeout: timeout,
  );

  test('Android path: SoundCloud in pure Dart; YouTube refused', () async {
    final scanner = LibraryScanner(
      db,
      coversDir: p.join(temp.path, 'covers'),
      downloadDir: p.join(temp.path, 'music'),
    );
    final phone = DownloadService(
      client: client,
      downloadDirectory: p.join(temp.path, 'music'),
      library: library,
      importFile: scanner.importFile,
      tagger: const DartTagger(),
    );
    final sc = await phone.resolve(
      'https://soundcloud.com/nocopyrightsounds/angelrot-backtoback-ncs',
    );
    await phone.download(sc.items.single, format: DownloadFormat.m4a);
    final track = (await library.watchTracks().first).single;
    expect(p.extension(track.path), '.mp3');
    expect(track.title, 'backtoback');
    expect(track.coverPath, isNotNull);

    final yt = await phone.resolve('https://youtu.be/vg95MYlTb3c');
    await expectLater(
      phone.download(yt.items.single, format: DownloadFormat.m4a),
      throwsA(
        isA<DownloadException>().having(
          (e) => e.reason,
          'reason',
          DownloadFailure.notOnThisDevice,
        ),
      ),
    );
  }, timeout: timeout);
}
