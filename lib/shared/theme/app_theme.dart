import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';

// App 整体主题（书架/搜索/设置等非阅读页面）。
// 阅读器正文配色在 ReaderSettings 中独立管理，不受此处影响。
class AppTheme {
  // 品牌主色种子（沿用项目原取色）
  static const _seed = Color(0xFF6B5B95);

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

  static ThemeData dark() => FlexThemeData.dark(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        subThemesData: _subThemes,
      );
}
