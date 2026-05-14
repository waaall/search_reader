import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../domain/reader_settings.dart';

// settings 表里使用的键名
class _Keys {
  static const fontSize = 'reader.font_size';
  static const lineHeight = 'reader.line_height';
  static const theme = 'reader.theme';
}

// 阅读器设置：在数据库 settings 表中持久化
class ReaderSettingsNotifier extends AsyncNotifier<ReaderSettings> {
  final SettingsDao _dao = SettingsDao();

  @override
  Future<ReaderSettings> build() async {
    final fontSizeName = await _dao.get(_Keys.fontSize);
    final lineHeightName = await _dao.get(_Keys.lineHeight);
    final themeName = await _dao.get(_Keys.theme);

    return ReaderSettings(
      fontSize: _parseEnum(FontSizeLevel.values, fontSizeName,
          fallback: FontSizeLevel.medium),
      lineHeight: _parseEnum(LineHeightLevel.values, lineHeightName,
          fallback: LineHeightLevel.normal),
      theme: _parseEnum(ReaderThemeMode.values, themeName,
          fallback: ReaderThemeMode.light),
    );
  }

  Future<void> updateFontSize(FontSizeLevel level) async {
    await _dao.set(_Keys.fontSize, level.name);
    state = AsyncData(state.value!.copyWith(fontSize: level));
  }

  Future<void> updateLineHeight(LineHeightLevel level) async {
    await _dao.set(_Keys.lineHeight, level.name);
    state = AsyncData(state.value!.copyWith(lineHeight: level));
  }

  Future<void> updateTheme(ReaderThemeMode theme) async {
    await _dao.set(_Keys.theme, theme.name);
    state = AsyncData(state.value!.copyWith(theme: theme));
  }

  // enum.name 反序列化（找不到时回退默认）
  T _parseEnum<T extends Enum>(List<T> values, String? name,
      {required T fallback}) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

final readerSettingsProvider =
    AsyncNotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  ReaderSettingsNotifier.new,
);
