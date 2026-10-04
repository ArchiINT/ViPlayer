import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viplayer/core/library/library_models.dart';
import 'package:viplayer/core/settings/settings_providers.dart';
import 'package:viplayer/features/library/library_screen.dart';

void main() {
  test('the library sort survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer app() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    final first = app();
    expect(first.read(trackSortProvider), TrackSort.title);
    await first.read(trackSortProvider.notifier).set(TrackSort.recentlyAdded);
    first.dispose();

    final second = app();
    expect(second.read(trackSortProvider), TrackSort.recentlyAdded);
    second.dispose();
  });
}
