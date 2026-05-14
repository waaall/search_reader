import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 数据库版本：每次 Schema 变更需要 +1
// v2：FTS5 trigram → unicode61 + bigram 化的 search 列；chapters 加 content 列
// 升级策略：drop & recreate（旧数据不保留，需要重新导入）
const int _kDbVersion = 2;
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
      throw StateError('AppDatabase 尚未初始化，请先调用 AppDatabase.init()');
    }
    return inst;
  }

  // 入口：在 main() 里调用一次
  static Future<void> init() async {
    if (_instance != null) return;

    // 桌面平台需要切到 ffi 后端；移动端使用平台默认实现
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _kDbFileName);

    final db = await openDatabase(
      path,
      version: _kDbVersion,
      onConfigure: (db) async {
        // 启用外键级联删除（books → chapters / progress）
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldV, newV) async {
        // drop & recreate：旧数据全部丢弃，结构按新版重建
        await _dropSchema(db);
        await _createSchema(db);
      },
    );

    _instance = AppDatabase._(db);
  }

  // 仅供测试或显式关闭场景使用
  static Future<void> close() async {
    await _instance?._db.close();
    _instance = null;
  }
}

// 全套 DDL：每次表/索引变更同步更新此函数，并提升 _kDbVersion
Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE books (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      author TEXT,
      file_path TEXT NOT NULL,
      encoding TEXT NOT NULL,
      total_chars INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      last_read_at INTEGER
    )
  ''');

  // chapters.content 存章节原文：搜索结果生成 snippet 用
  // （reader 仍走沙盒文件 + 起止位置截取的旧路径，互不影响）
  await db.execute('''
    CREATE TABLE chapters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id INTEGER NOT NULL,
      chapter_index INTEGER NOT NULL,
      title TEXT NOT NULL,
      start_char INTEGER NOT NULL,
      end_char INTEGER NOT NULL,
      content TEXT NOT NULL,
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
      'CREATE INDEX idx_chapters_book ON chapters(book_id, chapter_index)');

  await db.execute('''
    CREATE TABLE reading_progress (
      book_id INTEGER PRIMARY KEY,
      chapter_index INTEGER NOT NULL,
      char_offset INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    )
  ''');

  // 全文索引：unicode61 分词器（按空白切分），title/search 列存 bigram 化序列
  // 选择 bigram 而非 trigram：让 ≥2 字符的中文关键词也能搜到（trigram 至少要 3 字）
  // 不用 contentless 模式：老版本 SQLite（Android 13 及以下）不支持 contentless DELETE
  // 代价：FTS5 表内多存一份 bigram 序列（约原文 2x），换来跨平台稳定的 DELETE
  // snippet 不依赖 FTS5 内部内容，由 Dart 侧从 chapters.content 生成
  await db.execute('''
    CREATE VIRTUAL TABLE chapters_fts USING fts5(
      title,
      search,
      tokenize='unicode61'
    )
  ''');

  await db.execute('''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
}

// 删除全部表：升级时先 drop 再 recreate
// 顺序无所谓（外键约束 PRAGMA foreign_keys 是会话级，drop 时不强制）
// settings 也一并清空：阅读偏好不算关键数据，重设成本低
Future<void> _dropSchema(Database db) async {
  await db.execute('DROP TABLE IF EXISTS chapters_fts');
  await db.execute('DROP TABLE IF EXISTS reading_progress');
  await db.execute('DROP TABLE IF EXISTS chapters');
  await db.execute('DROP TABLE IF EXISTS books');
  await db.execute('DROP TABLE IF EXISTS settings');
}
