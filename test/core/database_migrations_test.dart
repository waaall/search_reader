// 数据库迁移测试：确认渲染分片表可新建、可从 v1 升级，并拒绝未登记版本。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/db/database_migrations.dart';
import 'package:search_reader/core/db/database_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('当前 v2 结构包含渲染分片表', () async {
    final tempDir = await Directory.systemTemp.createTemp('search_reader_v2_');
    final databasePath = p.join(tempDir.path, 'v2.db');

    try {
      final db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: DatabaseSchema.version,
          onConfigure: (database) async {
            await database.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (database, _) => DatabaseSchema.create(database),
        ),
      );

      expect(DatabaseSchema.version, 2);
      expect(await db.getVersion(), 2);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual table')",
        ),
        isNotEmpty,
      );

      final chapterColumns = await db.rawQuery('PRAGMA table_info(chapters)');
      final byteColumns = chapterColumns
          .where(
            (column) =>
                column['name'] == 'start_byte' || column['name'] == 'end_byte',
          )
          .toList();
      expect(byteColumns, hasLength(2));
      expect(byteColumns.every((column) => column['notnull'] == 1), isTrue);
      expect(
        byteColumns.every((column) => column['dflt_value'] == null),
        isTrue,
      );
      final segmentColumns = await db.rawQuery(
        'PRAGMA table_info(render_segments)',
      );
      expect(
        segmentColumns.map((column) => column['name']),
        containsAll([
          'chapter_id',
          'segment_index',
          'start_char',
          'end_char',
          'start_byte',
          'end_byte',
        ]),
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      await db.close();
    } finally {
      await databaseFactoryFfi.deleteDatabase(databasePath);
      await tempDir.delete(recursive: true);
    }
  });

  test('v1 升级到 v2 时保留章节并留待首次打开补建分片', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'search_reader_v1_to_v2_',
    );
    final databasePath = p.join(tempDir.path, 'upgrade.db');

    try {
      var db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, _) async {
            await DatabaseSchema.createBooks(database);
            await DatabaseSchema.createChaptersTable(database);
            await DatabaseSchema.createChaptersIndex(database);
            await DatabaseSchema.createReadingProgress(database);
            await DatabaseSchema.createChaptersFts(database);
            await DatabaseSchema.createSettings(database);
            await DatabaseSchema.createBookmarks(database);
            await DatabaseSchema.createImportJobs(database);
          },
        ),
      );
      final bookId = await db.insert('books', {
        'title': '旧书',
        'file_path': 'books/old.txt',
        'encoding': 'utf-8',
        'total_chars': 4,
        'created_at': 1,
      });
      await db.insert('chapters', {
        'book_id': bookId,
        'chapter_index': 0,
        'title': '正文',
        'start_char': 0,
        'end_char': 4,
        'start_byte': 0,
        'end_byte': 12,
      });
      await db.close();

      db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: migrateDatabase,
        ),
      );
      expect(await db.query('chapters'), hasLength(1));
      expect(await db.query('render_segments'), isEmpty);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    } finally {
      await databaseFactoryFfi.deleteDatabase(databasePath);
      await tempDir.delete(recursive: true);
    }
  });

  test('缺少未来版本迁移时快速失败', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'search_reader_missing_migration_',
    );
    final databasePath = p.join(tempDir.path, 'missing.db');

    try {
      final db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: DatabaseSchema.version,
          onCreate: (database, _) => DatabaseSchema.create(database),
        ),
      );

      await expectLater(migrateDatabase(db, 2, 3), throwsA(isA<StateError>()));
      await db.close();
    } finally {
      await databaseFactoryFfi.deleteDatabase(databasePath);
      await tempDir.delete(recursive: true);
    }
  });

  test('不允许数据库降级', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'search_reader_downgrade_',
    );
    final databasePath = p.join(tempDir.path, 'downgrade.db');

    try {
      final db = await databaseFactoryFfi.openDatabase(databasePath);

      await expectLater(migrateDatabase(db, 2, 1), throwsA(isA<StateError>()));
      await db.close();
    } finally {
      await databaseFactoryFfi.deleteDatabase(databasePath);
      await tempDir.delete(recursive: true);
    }
  });
}
