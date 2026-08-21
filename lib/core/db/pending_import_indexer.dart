// 待导入书籍索引器：文件读取和分词都在数据库事务外执行，只分批提交 FTS 行。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../parser/book_format.dart';
import 'text_index_worker.dart';

// 批次只限制数据库占用时间和待提交 token 的数量，不限制单个章节大小。
const _kIndexBatchChapterCount = 16;
const _kIndexBatchTokenChars = 1024 * 1024;

typedef PendingChapterReader =
    Future<String> Function(ChapterDescriptor chapter);

typedef PendingChapterIndexer =
    Future<ChapterIndexTokens> Function(String title, String content);

Future<void> indexPendingImport(
  Database db, {
  required int bookId,
  required PendingChapterReader readChapter,
  PendingChapterIndexer? buildIndex,
}) async {
  final jobRows = await db.query(
    'import_jobs',
    columns: ['state'],
    where: 'book_id = ?',
    whereArgs: [bookId],
    limit: 1,
  );
  if (jobRows.isEmpty) {
    throw StateError('找不到待导入任务：book_id=$bookId');
  }

  final state = jobRows.single['state'] as String;
  if (state == 'ready_to_finalize') return;
  if (state != 'indexing') {
    throw StateError('待导入任务状态无效：book_id=$bookId，state=$state');
  }

  // 只取还没有 FTS 行的章节，启动恢复时可以从上次中断处继续。
  final chapterRows = await db.rawQuery(
    '''
    SELECT
      c.id,
      c.title,
      c.start_char,
      c.end_char,
      c.start_byte,
      c.end_byte
    FROM chapters c
    LEFT JOIN chapters_fts f ON f.rowid = c.id
    WHERE c.book_id = ? AND f.rowid IS NULL
    ORDER BY c.chapter_index ASC
    ''',
    [bookId],
  );

  TextIndexWorker? ownedWorker;
  if (buildIndex == null) {
    // 恢复流程没有调用方 worker 时，也不能把分词重新放回主 isolate。
    ownedWorker = TextIndexWorker();
  }

  final pendingRows = <_PendingIndexRow>[];
  var pendingTokenChars = 0;
  try {
    for (final row in chapterRows) {
      final chapter = _chapterFromRow(row);
      final content = await readChapter(chapter);
      final tokens = buildIndex == null
          ? await ownedWorker!.tokenize(title: chapter.title, content: content)
          : await buildIndex(chapter.title, content);
      final indexedRow = _PendingIndexRow(
        chapterId: row['id']! as int,
        tokens: tokens,
      );
      pendingRows.add(indexedRow);
      pendingTokenChars += indexedRow.tokenChars;

      if (pendingRows.length >= _kIndexBatchChapterCount ||
          pendingTokenChars >= _kIndexBatchTokenChars) {
        await _commitIndexBatch(db, pendingRows);
        pendingRows.clear();
        pendingTokenChars = 0;
      }
    }

    await _commitIndexBatch(db, pendingRows);
  } finally {
    await ownedWorker?.close();
  }

  // 只有所有缺失章节都成功写入后，任务才允许进入文件发布阶段。
  final changed = await db.update(
    'import_jobs',
    {'state': 'ready_to_finalize'},
    where: 'book_id = ? AND state = ?',
    whereArgs: [bookId, 'indexing'],
  );
  if (changed != 1) {
    throw StateError('更新待导入任务状态失败：book_id=$bookId');
  }
}

ChapterDescriptor _chapterFromRow(Map<String, Object?> row) {
  return ChapterDescriptor(
    title: row['title']! as String,
    startChar: row['start_char']! as int,
    endChar: row['end_char']! as int,
    startByte: row['start_byte']! as int,
    endByte: row['end_byte']! as int,
  );
}

Future<void> _commitIndexBatch(Database db, List<_PendingIndexRow> rows) async {
  if (rows.isEmpty) return;

  // batch.commit 只包住 FTS INSERT，不包含文件读取和 isolate 等待。
  final batch = db.batch();
  for (final row in rows) {
    batch.insert('chapters_fts', {
      'rowid': row.chapterId,
      'title': row.tokens.title,
      'search': row.tokens.search,
    });
  }
  await batch.commit(noResult: true);
}

class _PendingIndexRow {
  final int chapterId;
  final ChapterIndexTokens tokens;

  const _PendingIndexRow({required this.chapterId, required this.tokens});

  int get tokenChars => tokens.title.length + tokens.search.length;
}
