import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viplayer/app.dart';
import 'package:viplayer/core/settings/settings_providers.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> _pumpApp(WidgetTester tester, SharedPreferences prefs) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const ViPlayerApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts on the library tab in English by default', (
    tester,
  ) async {
    await _pumpApp(tester, await _prefs());

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('restores the saved language', (tester) async {
    await _pumpApp(tester, await _prefs({'settings.language': 'ru'}));

    expect(find.text('Медиатека пуста'), findsOneWidget);
  });

  testWidgets('switching language in settings updates the UI and persists', (
    tester,
  ) async {
    final prefs = await _prefs();
    await _pumpApp(tester, prefs);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RU'));
    await tester.pumpAndSettle();

    expect(find.text('// ОФОРМЛЕНИЕ'), findsOneWidget);
    expect(prefs.getString('settings.language'), 'ru');
  });
}
