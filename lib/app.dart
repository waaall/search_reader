import 'package:flutter/material.dart';

import 'features/library/library_page.dart';
import 'shared/theme/app_theme.dart';

class SearchReaderApp extends StatelessWidget {
  const SearchReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小说阅读器',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const LibraryPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
