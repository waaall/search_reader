import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/application_data_recovery_provider.dart';
import 'features/library/library_page.dart';
import 'features/settings/app_locale_provider.dart';
import 'l10n/app_localizations.dart';
import 'shared/theme/app_theme.dart';

class SearchReaderApp extends ConsumerStatefulWidget {
  const SearchReaderApp({super.key});

  @override
  ConsumerState<SearchReaderApp> createState() => _SearchReaderAppState();
}

class _SearchReaderAppState extends ConsumerState<SearchReaderApp> {
  @override
  void initState() {
    super.initState();
    // 数据库已经打开后先完成首帧，再启动可能读取大量章节的恢复任务。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(applicationDataRecoveryProvider.notifier).recover());
    });
  }

  @override
  Widget build(BuildContext context) {
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
