import 'package:flutter/material.dart';

// 字号档位（pt 为单位的字体大小）
enum FontSizeLevel {
  small(16),
  medium(18),
  large(22),
  extraLarge(26);

  final double size;
  const FontSizeLevel(this.size);
}

// 行距档位（行高倍数）
enum LineHeightLevel {
  compact(1.4),
  normal(1.7),
  relaxed(2.0);

  final double multiplier;
  const LineHeightLevel(this.multiplier);
}

// 阅读器主题：背景与正文颜色
enum ReaderThemeMode {
  light(
    background: Color(0xFFFAFAF8),
    foreground: Color(0xFF24262B),
  ),
  dark(
    background: Color(0xFF191B1F),
    foreground: Color(0xFFD7D9DE),
  ),
  sepia(
    background: Color(0xFFF4ECD9),
    foreground: Color(0xFF57483A),
  );

  final Color background;
  final Color foreground;

  const ReaderThemeMode({
    required this.background,
    required this.foreground,
  });
}

// 阅读模式：翻页 / 滚动
enum ReadingMode {
  paginated,
  scroll;
}

@immutable
class ReaderSettings {
  final FontSizeLevel fontSize;
  final LineHeightLevel lineHeight;
  final ReaderThemeMode theme;
  final ReadingMode readingMode;

  const ReaderSettings({
    this.fontSize = FontSizeLevel.medium,
    this.lineHeight = LineHeightLevel.normal,
    this.theme = ReaderThemeMode.light,
    this.readingMode = ReadingMode.paginated,
  });

  ReaderSettings copyWith({
    FontSizeLevel? fontSize,
    LineHeightLevel? lineHeight,
    ReaderThemeMode? theme,
    ReadingMode? readingMode,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      theme: theme ?? this.theme,
      readingMode: readingMode ?? this.readingMode,
    );
  }
}
