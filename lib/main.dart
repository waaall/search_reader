import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/database.dart';
import 'db_init_error_app.dart';

Future<void> main() async {
  // 初始化 Flutter 绑定（数据库、path_provider 都依赖这个）
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // 只打开数据库并执行迁移；章节级恢复在首帧后后台执行，避免启动白屏。
    await AppDatabase.init();
    runApp(const ProviderScope(child: SearchReaderApp()));
  } catch (e, st) {
    // 初始化失败不能卡在 runApp 之前导致黑屏：打印日志并显示兜底错误页
    debugPrint('数据库初始化失败: $e\n$st');
    runApp(DbInitErrorApp(error: e));
  }
}
