import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 数据库版本：每次 Schema 变更需要 +1，并在 _onUpgrade 中处理迁移
const int _kDbVersion = 1;
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
        // 后续版本迁移在这里增量处理
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

  await db.execute('''
    CREATE TABLE chapters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id INTEGER NOT NULL,
      chapter_index INTEGER NOT NULL,
      title TEXT NOT NULL,
      start_char INTEGER NOT NULL,
      end_char INTEGER NOT NULL,
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

  // 全文索引：trigram 分词器对中文搜索效果好
  // content='' 表示外部内容模式（rowid 是 chapters.id，行内不重复存储）
  await db.execute('''
    CREATE VIRTUAL TABLE chapters_fts USING fts5(
      title,
      content,
      tokenize='trigram'
    )
  ''');

  await db.execute('''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
}
