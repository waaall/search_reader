import 'package:flutter/material.dart';

// App 整体（书架/搜索/设置等非阅读页面）主题
// 阅读器自身的主题在 ReaderSettings 中独立管理
class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6B5B95),
        brightness: Brightness.light,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6B5B95),
        brightness: Brightness.dark,
      ),
    );
  }
}
