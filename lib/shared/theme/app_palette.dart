// 应用色板：以低饱和藏书蓝和中性纸面色为核心，统一浅色与深色界面。
// 阅读正文的三套专用配色仍由 ReaderThemeMode 管理，两者通过相同的克制对比保持一致。

import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const paper = Color(0xFFF6F7F9);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF20242C);
  static const mutedInk = Color(0xFF6E7580);
  static const libraryBlue = Color(0xFF4D5F9E);
  static const softBlue = Color(0xFFE9ECF6);
  static const divider = Color(0xFFDDE1E7);

  static const darkCanvas = Color(0xFF171A20);
  static const darkSurface = Color(0xFF1D2129);
  static const darkInk = Color(0xFFE4E7EC);
  static const darkMutedInk = Color(0xFFA9B0BC);
  static const darkLibraryBlue = Color(0xFFB9C3F5);
  static const darkSoftBlue = Color(0xFF303A60);
  static const darkDivider = Color(0xFF363C47);
}
