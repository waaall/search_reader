// 数据库初始化入口：负责打开数据库、执行版本迁移并在成功后清理孤儿文件。
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'application_data_recovery.dart';
import 'database_migrations.dart';
import 'database_schema.dart';

const String _kDbFileName = 'search_reader.db';

// 单例数据库句柄：通过 [appDatabase] 全局访问
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;
  Database get db => _db;

  static AppDatabase? _instance;
  static AppDatabase get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError(
        'AppDatabase is not initialized. Call AppDatabase.init() first.',
      );
    }
    return inst;
  }

  // 入口：在 main() 里调用一次
  static Future<void> init() async {
    if (_instance != null) return;

    // 全平台统一走 ffi 后端 + 自带 SQLite（由 sqlite3_flutter_libs 打包，含 FTS5）
    // 不依赖系统 SQLite：Android 系统库未编入 FTS5 模块，建 FTS5 表会失败
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _kDbFileName);

    final db = await openDatabase(
      path,
      version: DatabaseSchema.version,
      onConfigure: (db) async {
        // 启用外键级联删除（books → chapters / progress）
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await DatabaseSchema.create(db);
      },
      onUpgrade: (db, oldV, newV) async {
        // v1 之后只执行登记过的增量迁移；sqflite 会在事务中执行回调。
        await migrateDatabase(db, oldV, newV);
      },
    );

    // 每次启动都恢复未完成导入，并清理崩溃后遗留的坏记录和孤儿文件。
    await recoverApplicationData(db);

    _instance = AppDatabase._(db);
  }

  // 仅供测试或显式关闭场景使用
  static Future<void> close() async {
    await _instance?._db.close();
    _instance = null;
  }
}
