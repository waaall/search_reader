// 启动恢复流程：收敛数据库事务与文件系统操作之间可能残留的中间状态。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../storage/book_storage.dart';
import 'database_operations.dart';
import 'text_index.dart';

Future<void> recoverApplicationData(Database db, {BookStorage? storage}) async {
  final bookStorage = storage ?? BookStorage.shared;

  await _recoverPendingImports(db, bookStorage);
  await _removeBrokenBooks(db, bookStorage);
  await _repairFtsIndex(db, bookStorage);
  await _cleanupUnreferencedFiles(db, bookStorage);

  final violations = await db.rawQuery('PRAGMA foreign_key_check');
  if (violations.isNotEmpty) {
    throw StateError('启动完整性检查发现外键异常：$violations');
  }
}

Future<void> _recoverPendingImports(Database db, BookStorage storage) async {
  final jobs = await db.rawQuery('''
    SELECT job.book_id, job.staged_path, job.target_path
    FROM import_jobs job
    JOIN books b ON b.id = job.book_id
    ORDER BY job.created_at
  ''');

  for (final job in jobs) {
    final bookId = job['book_id'] as int;
    final stagedFile = StagedBookFile(
      stagedPath: job['staged_path'] as String,
      targetPath: job['target_path'] as String,
    );
    final stagedExists = await storage.exists(stagedFile.stagedPath);
    final targetExists = await storage.exists(stagedFile.targetPath);

    if (!stagedExists && !targetExists) {
      // 文件两端都不存在，数据库半成品已无法恢复，整组删除避免坏书进入书架。
      await deleteBookRecords(db, bookId);
      continue;
    }

    try {
      await storage.finalizeStagedFile(stagedFile);
      await db.delete('import_jobs', where: 'book_id = ?', whereArgs: [bookId]);
    } catch (_) {
      // 单个文件恢复失败时保留日志和临时文件，下次启动继续重试。
    }
  }
}

Future<void> _removeBrokenBooks(Database db, BookStorage storage) async {
  final books = await db.rawQuery('''
    SELECT b.id, b.file_path, COUNT(c.id) AS chapter_count
    FROM books b
    LEFT JOIN chapters c ON c.book_id = b.id
    WHERE NOT EXISTS (
      SELECT 1 FROM import_jobs job WHERE job.book_id = b.id
    )
    GROUP BY b.id, b.file_path
  ''');

  for (final book in books) {
    final bookId = book['id'] as int;
    final chapterCount = book['chapter_count'] as int;
    if (chapterCount == 0) {
      await deleteBookRecords(db, bookId);
      continue;
    }

    final availability = await storage.inspectAvailability(
      book['file_path'] as String,
    );
    if (availability == BookFileAvailability.missing) {
      // 只有存储层明确确认文件不存在时才删除；检查异常时保留数据并继续启动。
      await deleteBookRecords(db, bookId);
    }
  }
}

Future<void> _repairFtsIndex(Database db, BookStorage storage) async {
  // 先移除没有章节元数据的 FTS 行。
  final orphanedRows = await db.rawQuery('''
    SELECT f.rowid
    FROM chapters_fts f
    LEFT JOIN chapters c ON c.id = f.rowid
    WHERE c.id IS NULL
  ''');
  for (final row in orphanedRows) {
    await db.delete(
      'chapters_fts',
      where: 'rowid = ?',
      whereArgs: [row['rowid']],
    );
  }

  // 缺失索引可以从正式书籍文件按章节字符范围重新构建。
  final missingRows = await db.rawQuery('''
    SELECT
      c.id,
      c.title,
      c.start_char,
      c.end_char,
      b.id AS book_id,
      b.file_path
    FROM chapters c
    JOIN books b ON b.id = c.book_id
    LEFT JOIN chapters_fts f ON f.rowid = c.id
    WHERE f.rowid IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM import_jobs job WHERE job.book_id = b.id
      )
    ORDER BY b.id, c.chapter_index
  ''');
  final textCache = <int, String>{};
  for (final row in missingRows) {
    try {
      final bookId = row['book_id'] as int;
      final fullText = textCache[bookId] ??= await storage.readFullText(
        row['file_path'] as String,
      );
      final start = (row['start_char'] as int).clamp(0, fullText.length);
      final end = (row['end_char'] as int).clamp(start, fullText.length);
      final content = fullText.substring(start, end);
      await db.insert('chapters_fts', {
        'rowid': row['id'],
        'title': toBigramTokens(row['title'] as String),
        'search': toBigramTokens(content),
      });
    } catch (_) {
      // 单章修复失败不阻止启动；下次启动仍会再次检测并尝试重建。
    }
  }
}

Future<void> _cleanupUnreferencedFiles(Database db, BookStorage storage) async {
  final bookRows = await db.query('books', columns: ['file_path']);
  final referencedBooks = bookRows
      .map((row) => row['file_path'])
      .whereType<String>()
      .toSet();

  final jobRows = await db.query('import_jobs', columns: ['staged_path']);
  final registeredStagedFiles = jobRows
      .map((row) => row['staged_path'])
      .whereType<String>()
      .toSet();

  try {
    await storage.deleteUnreferencedFiles(referencedBooks);
  } catch (_) {
    // 文件残留不影响数据库一致性，保留到下次启动继续清理。
  }
  try {
    await storage.deleteUnregisteredStagedFiles(registeredStagedFiles);
  } catch (_) {
    // 临时文件清理同样采用尽力而为策略。
  }
}
