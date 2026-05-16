import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';

// App 整体主题（书架/搜索/设置等非阅读页面）。
// 阅读器正文配色在 ReaderSettings 中独立管理，不受此处影响。
class AppTheme {
  // 品牌主色种子（沿用项目原取色）
  static const _seed = Color(0xFF6B5B95);

  // 深色主题主背景灰（中等深度，避免纯黑高对比刺眼）：surface 与脚手架背景共用
  static const _darkSurface = Color(0xFF1F1F1F);

  // 组件级 sub-theme：圆角、卡片阴影等一次性铺到所有 Material 控件
  static const _subThemes = FlexSubThemesData(
    defaultRadius: AppRadius.md,
    cardElevation: 1.0,
    interactionEffects: true,
    tintedDisabledControls: true,
  );

  static ThemeData light() => FlexThemeData.light(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
        ),
        subThemesData: _subThemes,
      );

  static ThemeData dark() {
    // 保留 fromSeed 生成的品牌紫强调色，但把 surface 一组覆写成中性灰，
    // 去掉 Material 3 渗进背景的紫调；正文文字压成浅灰，降低刺眼的高对比
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: _darkSurface,
      surfaceDim: const Color(0xFF161616),
      surfaceBright: const Color(0xFF3A3A3A),
      surfaceContainerLowest: const Color(0xFF121212),
      surfaceContainerLow: const Color(0xFF1B1B1B),
      surfaceContainer: const Color(0xFF242424),
      surfaceContainerHigh: const Color(0xFF2C2C2C),
      surfaceContainerHighest: const Color(0xFF353535),
      onSurface: const Color(0xFFE3E3E3),
      onSurfaceVariant: const Color(0xFFBDBDBD),
      outline: const Color(0xFF8C8C8C),
      outlineVariant: const Color(0xFF3D3D3D),
      inverseSurface: const Color(0xFFE3E3E3),
      onInverseSurface: const Color(0xFF2E2E2E),
      surfaceTint: _darkSurface,
    );
    return FlexThemeData.dark(
      colorScheme: colorScheme,
      scaffoldBackground: _darkSurface,
      subThemesData: _subThemes,
    );
  }
}
