// 当前数据库结构定义：新建数据库和增量迁移复用同一组建表方法。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

abstract final class DatabaseSchema {
  // 正式 v1 以当前结构为基线；后续结构变更必须递增版本并注册对应迁移。
  static const int version = 1;

  static Future<void> create(DatabaseExecutor db) async {
    await createBooks(db);
    await createChaptersTable(db);
    await createChaptersIndex(db);
    await createReadingProgress(db);
    await createChaptersFts(db);
    await createSettings(db);
    await createBookmarks(db);
    await createImportJobs(db);
  }

  static Future<void> createBooks(DatabaseExecutor db) async {
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
  }

  static Future<void> createChaptersTable(DatabaseExecutor db) async {
    // 正文保存在沙盒文件中；数据库只记录章节元数据和字符范围。
    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter_index INTEGER NOT NULL,
        title TEXT NOT NULL,
        start_char INTEGER NOT NULL,
        end_char INTEGER NOT NULL,
        start_byte INTEGER NOT NULL,
        end_byte INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> createChaptersIndex(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX idx_chapters_book ON chapters(book_id, chapter_index)',
    );
  }

  static Future<void> createReadingProgress(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE reading_progress (
        book_id INTEGER PRIMARY KEY,
        chapter_index INTEGER NOT NULL,
        char_offset INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> createChaptersFts(DatabaseExecutor db) async {
    // title/search 保存 bigram token；正文片段仍从沙盒文件按字符范围读取。
    await db.execute('''
      CREATE VIRTUAL TABLE chapters_fts USING fts5(
        title,
        search,
        tokenize='unicode61'
      )
    ''');
  }

  static Future<void> createSettings(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> createBookmarks(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter_index INTEGER NOT NULL,
        char_offset INTEGER NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_bookmarks_pos '
      'ON bookmarks(book_id, chapter_index, char_offset)',
    );
    await db.execute(
      'CREATE INDEX idx_bookmarks_book '
      'ON bookmarks(book_id, created_at DESC)',
    );
  }

  static Future<void> createImportJobs(DatabaseExecutor db) async {
    // 记录数据库已提交、但沙盒文件尚未从临时路径原子发布的导入任务。
    await db.execute('''
      CREATE TABLE import_jobs (
        book_id INTEGER PRIMARY KEY,
        staged_path TEXT NOT NULL,
        target_path TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state IN ('indexing', 'ready_to_finalize')),
        created_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
  }
}
