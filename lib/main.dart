import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/database.dart';

Future<void> main() async {
  // 初始化 Flutter 绑定（数据库、path_provider 都依赖这个）
  WidgetsFlutterBinding.ensureInitialized();
  // 数据库初始化（移动端 + 桌面端 ffi 适配在 AppDatabase.init 内处理）
  await AppDatabase.init();
  runApp(const ProviderScope(child: SearchReaderApp()));
}
