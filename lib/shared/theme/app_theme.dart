import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

// App 整体主题（书架/搜索/设置等非阅读页面）。
// 阅读器正文配色在 ReaderSettings 中独立管理，不受此处影响。
class AppTheme {
  // 组件级 sub-theme：卡片采用零阴影，主要通过浅表面和细描边建立层级。
  static const _subThemes = FlexSubThemesData(
    defaultRadius: AppRadius.md,
    cardElevation: 0,
    interactionEffects: true,
    tintedDisabledControls: true,
  );

  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.libraryBlue,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppPalette.libraryBlue,
          onPrimary: Colors.white,
          primaryContainer: AppPalette.softBlue,
          onPrimaryContainer: const Color(0xFF26315A),
          secondary: const Color(0xFF66708F),
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFECEEF4),
          onSecondaryContainer: const Color(0xFF282E3E),
          surface: AppPalette.surface,
          surfaceDim: const Color(0xFFEEF0F3),
          surfaceBright: AppPalette.surface,
          surfaceContainerLowest: AppPalette.surface,
          surfaceContainerLow: AppPalette.paper,
          surfaceContainer: const Color(0xFFF0F2F5),
          surfaceContainerHigh: const Color(0xFFE9ECF0),
          surfaceContainerHighest: const Color(0xFFE2E5EA),
          onSurface: AppPalette.ink,
          onSurfaceVariant: AppPalette.mutedInk,
          outline: const Color(0xFFAEB4BE),
          outlineVariant: AppPalette.divider,
          surfaceTint: Colors.transparent,
        );
    return FlexThemeData.light(
      colorScheme: colorScheme,
      scaffoldBackground: AppPalette.paper,
      subThemesData: _subThemes,
    ).copyWith(
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppPalette.paper,
        foregroundColor: AppPalette.ink,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.darkLibraryBlue,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppPalette.darkLibraryBlue,
          onPrimary: const Color(0xFF202A50),
          primaryContainer: AppPalette.darkSoftBlue,
          onPrimaryContainer: const Color(0xFFE0E5FF),
          secondary: const Color(0xFFB8C0D8),
          onSecondary: const Color(0xFF292F3F),
          secondaryContainer: const Color(0xFF343A49),
          onSecondaryContainer: const Color(0xFFE2E6F2),
          surface: AppPalette.darkSurface,
          surfaceDim: const Color(0xFF13161B),
          surfaceBright: const Color(0xFF343A44),
          surfaceContainerLowest: const Color(0xFF12151A),
          surfaceContainerLow: AppPalette.darkCanvas,
          surfaceContainer: AppPalette.darkSurface,
          surfaceContainerHigh: const Color(0xFF272C35),
          surfaceContainerHighest: const Color(0xFF303640),
          onSurface: AppPalette.darkInk,
          onSurfaceVariant: AppPalette.darkMutedInk,
          outline: const Color(0xFF737B89),
          outlineVariant: AppPalette.darkDivider,
          inverseSurface: AppPalette.darkInk,
          onInverseSurface: AppPalette.darkSurface,
          surfaceTint: Colors.transparent,
        );
    return FlexThemeData.dark(
      colorScheme: colorScheme,
      scaffoldBackground: AppPalette.darkCanvas,
      subThemesData: _subThemes,
    ).copyWith(
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppPalette.darkCanvas,
        foregroundColor: AppPalette.darkInk,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
