import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';

// App 显示语言：system 表示跟随系统；其余值会覆盖 MaterialApp.locale。
enum AppLocaleMode {
  system,
  simplifiedChinese,
  english;

  Locale? get locale => switch (this) {
    AppLocaleMode.system => null,
    AppLocaleMode.simplifiedChinese => const Locale('zh'),
    AppLocaleMode.english => const Locale('en'),
  };
}

class _Keys {
  static const appLocale = 'app.locale';
}

// 全局语言设置：在数据库 settings 表中持久化，切换后驱动 MaterialApp 立即重建。
class AppLocaleNotifier extends AsyncNotifier<AppLocaleMode> {
  final SettingsDao _dao = SettingsDao();

  @override
  Future<AppLocaleMode> build() async {
    final localeName = await _dao.get(_Keys.appLocale);
    return _parseEnum(
      AppLocaleMode.values,
      localeName,
      fallback: AppLocaleMode.system,
    );
  }

  Future<void> updateLocaleMode(AppLocaleMode mode) async {
    await _dao.set(_Keys.appLocale, mode.name);
    state = AsyncData(mode);
  }

  // enum.name 反序列化（找不到时回退默认）
  T _parseEnum<T extends Enum>(
    List<T> values,
    String? name, {
    required T fallback,
  }) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

final appLocaleProvider =
    AsyncNotifierProvider<AppLocaleNotifier, AppLocaleMode>(
      AppLocaleNotifier.new,
    );
