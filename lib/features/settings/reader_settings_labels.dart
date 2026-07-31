// 阅读设置选项的本地化标签。
// 完整设置页与阅读页快捷设置共用这些映射，避免同一枚举在多个界面重复维护。

import 'package:flutter/widgets.dart';

import '../../domain/reader_settings.dart';
import '../../shared/l10n/app_l10n.dart';

String readerFontSizeLabel(BuildContext context, FontSizeLevel level) {
  final l10n = context.l10n;
  return switch (level) {
    FontSizeLevel.small => l10n.fontSizeSmall,
    FontSizeLevel.medium => l10n.fontSizeMedium,
    FontSizeLevel.large => l10n.fontSizeLarge,
    FontSizeLevel.extraLarge => l10n.fontSizeExtraLarge,
  };
}

String readerLineHeightLabel(BuildContext context, LineHeightLevel level) {
  final l10n = context.l10n;
  return switch (level) {
    LineHeightLevel.compact => l10n.lineHeightCompact,
    LineHeightLevel.normal => l10n.lineHeightNormal,
    LineHeightLevel.relaxed => l10n.lineHeightRelaxed,
  };
}

String readerThemeLabel(BuildContext context, ReaderThemeMode mode) {
  final l10n = context.l10n;
  return switch (mode) {
    ReaderThemeMode.light => l10n.readerThemeLight,
    ReaderThemeMode.dark => l10n.readerThemeDark,
    ReaderThemeMode.sepia => l10n.readerThemeSepia,
  };
}

String readingModeLabel(BuildContext context, ReadingMode mode) {
  final l10n = context.l10n;
  return switch (mode) {
    ReadingMode.paginated => l10n.readingModePaginated,
    ReadingMode.scroll => l10n.readingModeScroll,
  };
}
