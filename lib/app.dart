import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/library/library_page.dart';
import 'features/settings/app_locale_provider.dart';
import 'l10n/app_localizations.dart';
import 'shared/theme/app_theme.dart';

class SearchReaderApp extends ConsumerWidget {
  const SearchReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeMode = ref.watch(appLocaleProvider).valueOrNull;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: localeMode?.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const LibraryPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
