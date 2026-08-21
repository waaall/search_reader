// 数据库基线测试：确认当前结构固定为正式 v1，并拒绝未登记的跨版本操作。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/db/database_migrations.dart';
import 'package:search_reader/core/db/database_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('当前结构作为正式 v1 创建', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'search_reader_v1_',
    );
    final databasePath = p.join(tempDir.path, 'v1.db');

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

      expect(DatabaseSchema.version, 1);
      expect(await db.getVersion(), 1);
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
                column['name'] == 'start_byte' ||
                column['name'] == 'end_byte',
          )
          .toList();
      expect(byteColumns, hasLength(2));
      expect(byteColumns.every((column) => column['notnull'] == 1), isTrue);
      expect(
        byteColumns.every((column) => column['dflt_value'] == null),
        isTrue,
      );
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

      await expectLater(
        migrateDatabase(db, 1, 2),
        throwsA(isA<StateError>()),
      );
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

      await expectLater(
        migrateDatabase(db, 2, 1),
        throwsA(isA<StateError>()),
      );
      await db.close();
    } finally {
      await databaseFactoryFfi.deleteDatabase(databasePath);
      await tempDir.delete(recursive: true);
    }
  });
}
