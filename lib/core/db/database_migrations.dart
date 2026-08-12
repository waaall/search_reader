// 数据库增量迁移：每个目标版本只负责从前一版本演进一步。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_schema.dart';
import 'text_index.dart';

typedef DatabaseMigration = Future<void> Function(Database db);

final Map<int, DatabaseMigration> _migrationsByTargetVersion = {
  2: _migrateV1ToV2,
  3: _migrateV2ToV3,
  4: _migrateV3ToV4,
  5: _migrateV4ToV5,
};

Future<void> migrateDatabase(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  for (
    var targetVersion = oldVersion + 1;
    targetVersion <= newVersion;
    targetVersion++
  ) {
    final migration = _migrationsByTargetVersion[targetVersion];
    if (migration == null) {
      throw StateError('缺少数据库 v${targetVersion - 1} → v$targetVersion 的迁移');
    }
    await migration(db);
  }

  // 在提交前校验外键，避免把结构正确但引用损坏的数据带入新版本。
  final violations = await db.rawQuery('PRAGMA foreign_key_check');
  if (violations.isNotEmpty) {
    throw StateError('数据库迁移产生了外键异常：$violations');
  }
}

Future<void> _migrateV1ToV2(Database db) async {
  // v1 的 FTS 表保存原始正文，先取出内容，再替换为 bigram FTS 结构。
  final chapters = await db.rawQuery('''
    SELECT c.id, c.title, COALESCE(f.content, '') AS content
    FROM chapters c
    LEFT JOIN chapters_fts f ON f.rowid = c.id
    ORDER BY c.id
  ''');

  await db.execute(
    "ALTER TABLE chapters ADD COLUMN content TEXT NOT NULL DEFAULT ''",
  );
  for (final chapter in chapters) {
    await db.update(
      'chapters',
      {'content': chapter['content'] as String},
      where: 'id = ?',
      whereArgs: [chapter['id']],
    );
  }

  await db.execute('DROP TABLE chapters_fts');
  await DatabaseSchema.createChaptersFts(db);
  for (final chapter in chapters) {
    await db.insert('chapters_fts', {
      'rowid': chapter['id'],
      'title': toBigramTokens(chapter['title'] as String),
      'search': toBigramTokens(chapter['content'] as String),
    });
  }
}

Future<void> _migrateV2ToV3(Database db) async {
  // v3 只新增书签，不改动书架、章节、进度、设置和全文索引。
  await DatabaseSchema.createBookmarks(db);
}

Future<void> _migrateV3ToV4(Database db) async {
  // SQLite 旧版本不一定支持 DROP COLUMN，通过重建表安全移除冗余正文列。
  await db.execute('ALTER TABLE chapters RENAME TO chapters_v3');
  await DatabaseSchema.createChaptersTable(db);
  await db.execute('''
    INSERT INTO chapters(id, book_id, chapter_index, title, start_char, end_char)
    SELECT id, book_id, chapter_index, title, start_char, end_char
    FROM chapters_v3
  ''');
  await db.execute('DROP TABLE chapters_v3');
  await DatabaseSchema.createChaptersIndex(db);
}

Future<void> _migrateV4ToV5(Database db) async {
  // v5 引入导入恢复日志，已有书籍均视为已经完成发布。
  await DatabaseSchema.createImportJobs(db);
}
