import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/settings/settings_providers.dart';
import 'core/theme/app_theme.dart';
import 'l10n/generated/app_localizations.dart';

class ViPlayerApp extends ConsumerWidget {
  const ViPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(settings.accent),
      themeMode: ThemeMode.dark,
      // Theme changes (accent switch) cross-fade instead of snapping.
      themeAnimationDuration: AppMotion.normal,
      locale: settings.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    );
  }
}
