import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:viplayer/core/player/play_order.dart';

void main() {
  final paths = ['a', 'b', 'c', 'd'];

  test('in order: continues after the start and wraps around', () {
    final order = PlayOrder(paths, shuffle: false, start: 2);
    expect(order.take(6), ['d', 'a', 'b', 'c', 'd', 'a']);
  });

  test('shuffled: whole rounds, no back-to-back repeats', () {
    for (var seed = 0; seed < 50; seed++) {
      final order = PlayOrder(
        paths,
        shuffle: true,
        start: 0,
        random: math.Random(seed),
      );
      final dealt = ['a', ...order.take(3 + 4 * 5)];
      expect(dealt.sublist(1, 4).toSet(), {'b', 'c', 'd'});
      for (var r = 4; r < dealt.length; r += 4) {
        expect(dealt.sublist(r, r + 4).toSet(), paths.toSet());
      }
      for (var i = 1; i < dealt.length; i++) {
        expect(dealt[i], isNot(dealt[i - 1]), reason: 'seed $seed at $i');
      }
    }
  });

  test('a one-track list repeats it; an empty one deals nothing', () {
    expect(PlayOrder(['a'], shuffle: true).take(3), ['a', 'a', 'a']);
    expect(PlayOrder(const [], shuffle: false).take(3), isEmpty);
  });

  test('switching mode continues after the current track', () {
    final order = PlayOrder(paths, shuffle: true);
    order.setShuffle(false, current: 'b');
    expect(order.take(3), ['c', 'd', 'a']);

    order.setShuffle(true, current: 'c');
    expect(order.take(3).toSet(), {'a', 'b', 'd'});
  });

  test('removed tracks are no longer dealt', () {
    final order = PlayOrder(paths, shuffle: false, start: 0)..remove('c');
    expect(order.take(4), ['b', 'd', 'a', 'b']);
  });

  test('survives a save/restore, dropping tracks that are gone', () {
    final order = PlayOrder(paths, shuffle: false, start: 0)..take(1); // b
    final restored = PlayOrder.fromJson(order.toJson(), (p) => p != 'a')!;
    expect(restored.take(3), ['c', 'd', 'b']);
    expect(PlayOrder.fromJson(order.toJson(), (_) => false), isNull);
  });
}
