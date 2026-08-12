// 数据库初始化入口：负责打开数据库、执行版本迁移并在成功后清理孤儿文件。
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../storage/book_storage.dart';
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
    var didUpgrade = false;

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
        // sqflite 会在事务中执行回调；任一步失败都会回滚且不会提升版本号。
        await migrateDatabase(db, oldV, newV);
        didUpgrade = true;
      },
    );

    // 文件系统不参与数据库事务，只能在迁移提交后按数据库白名单清理。
    if (didUpgrade) {
      await _deleteUnreferencedBookFiles(db);
    }

    _instance = AppDatabase._(db);
  }

  // 仅供测试或显式关闭场景使用
  static Future<void> close() async {
    await _instance?._db.close();
    _instance = null;
  }
}

Future<void> _deleteUnreferencedBookFiles(Database db) async {
  try {
    final rows = await db.query('books', columns: ['file_path']);
    final referencedPaths = rows
        .map((row) => row['file_path'])
        .whereType<String>()
        .toSet();
    await BookStorage.deleteUnreferencedFiles(referencedPaths);
  } catch (_) {
    // 清理失败不能影响已经成功提交的迁移；残留文件比误删或启动失败更安全。
  }
}
