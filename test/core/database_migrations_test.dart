// 数据库迁移回归测试：覆盖所有已发布版本直升当前版本的数据保留行为。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/db/database_migrations.dart';
import 'package:search_reader/core/db/database_schema.dart';
import 'package:search_reader/core/db/text_index.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _bookId = 7;
const _chapterId = 11;
const _bookPath = 'books/preserved.txt';
const _chapterTitle = '第一章';
const _chapterContent = '序章你好世界';

void main() {
  setUpAll(sqfliteFfiInit);

  for (final oldVersion in [1, 2, 3]) {
    test('v$oldVersion 升级到 v4 时保留用户数据', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'search_reader_migration_',
      );
      final databasePath = p.join(tempDir.path, 'migration.db');

      try {
        var db = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(
            version: oldVersion,
            onCreate: (db, version) => _createHistoricalSchema(db, version),
          ),
        );
        await _insertFixture(db, oldVersion);
        await db.close();

        db = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(
            version: DatabaseSchema.version,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onUpgrade: migrateDatabase,
          ),
        );

        await _expectFixtureWasPreserved(db, oldVersion);
        await db.close();
      } finally {
        await databaseFactoryFfi.deleteDatabase(databasePath);
        await tempDir.delete(recursive: true);
      }
    });
  }
}

Future<void> _createHistoricalSchema(Database db, int version) async {
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
      ${version >= 2 ? 'content TEXT NOT NULL,' : ''}
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_chapters_book ON chapters(book_id, chapter_index)',
  );
  await db.execute('''
    CREATE TABLE reading_progress (
      book_id INTEGER PRIMARY KEY,
      chapter_index INTEGER NOT NULL,
      char_offset INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
    )
  ''');
  if (version == 1) {
    await db.execute('''
      CREATE VIRTUAL TABLE chapters_fts USING fts5(
        title,
        content,
        tokenize='trigram'
      )
    ''');
  } else {
    await DatabaseSchema.createChaptersFts(db);
  }
  await DatabaseSchema.createSettings(db);
  if (version >= 3) {
    await DatabaseSchema.createBookmarks(db);
  }
}

Future<void> _insertFixture(Database db, int version) async {
  await db.insert('books', {
    'id': _bookId,
    'title': '保留的书',
    'author': '作者',
    'file_path': _bookPath,
    'encoding': 'utf-8',
    'total_chars': _chapterContent.length,
    'created_at': 1000,
    'last_read_at': 2000,
  });
  await db.insert('chapters', {
    'id': _chapterId,
    'book_id': _bookId,
    'chapter_index': 0,
    'title': _chapterTitle,
    'start_char': 0,
    'end_char': _chapterContent.length,
    if (version >= 2) 'content': _chapterContent,
  });
  await db.insert('chapters_fts', {
    'rowid': _chapterId,
    'title': version == 1 ? _chapterTitle : toBigramTokens(_chapterTitle),
    version == 1 ? 'content' : 'search': version == 1
        ? _chapterContent
        : toBigramTokens(_chapterContent),
  });
  await db.insert('reading_progress', {
    'book_id': _bookId,
    'chapter_index': 0,
    'char_offset': 3,
    'updated_at': 3000,
  });
  await db.insert('settings', {'key': 'reader.fontSize', 'value': '20'});
  if (version >= 3) {
    await db.insert('bookmarks', {
      'id': 13,
      'book_id': _bookId,
      'chapter_index': 0,
      'char_offset': 4,
      'note': '保留的书签',
      'created_at': 4000,
    });
  }
}

Future<void> _expectFixtureWasPreserved(Database db, int oldVersion) async {
  expect(await db.getVersion(), DatabaseSchema.version);

  final books = await db.query('books', where: 'id = ?', whereArgs: [_bookId]);
  expect(books.single['file_path'], _bookPath);
  expect(books.single['last_read_at'], 2000);

  final chapters = await db.query(
    'chapters',
    where: 'id = ?',
    whereArgs: [_chapterId],
  );
  expect(chapters.single['title'], _chapterTitle);
  final chapterColumns = await db.rawQuery('PRAGMA table_info(chapters)');
  expect(
    chapterColumns.map((column) => column['name']),
    isNot(contains('content')),
  );

  final progress = await db.query('reading_progress');
  expect(progress.single['char_offset'], 3);
  final settings = await db.query('settings');
  expect(settings.single, containsPair('value', '20'));

  final bookmarks = await db.query('bookmarks');
  expect(bookmarks.length, oldVersion >= 3 ? 1 : 0);
  if (oldVersion >= 3) {
    expect(bookmarks.single['note'], '保留的书签');
  }

  final matches = await db.rawQuery(
    'SELECT rowid FROM chapters_fts WHERE chapters_fts MATCH ?',
    [toBigramQuery('你好')],
  );
  expect(matches.single['rowid'], _chapterId);
  expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
}
