// 启动恢复流程：收敛数据库事务与文件系统操作之间可能残留的中间状态。
// 恢复可能需要读取大量章节，因此这里只负责数据修复、进度回调和结果汇总；
// 调用方决定何时启动以及如何把状态展示给用户。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../storage/book_storage.dart';
import 'application_data_operation_coordinator.dart';
import 'database_operations.dart';
import 'pending_import_indexer.dart';
import 'text_index_worker.dart';

enum ApplicationDataRecoveryPhase {
  resumingImports,
  finalizingImports,
  checkingBooks,
  rebuildingSearchIndex,
  cleaningFiles,
  validatingDatabase,
}

class ApplicationDataRecoveryProgress {
  final ApplicationDataRecoveryPhase phase;
  final int completed;
  final int total;

  const ApplicationDataRecoveryProgress({
    required this.phase,
    required this.completed,
    required this.total,
  });

  double? get fraction {
    if (total <= 0) return null;
    return (completed / total).clamp(0.0, 1.0).toDouble();
  }
}

typedef ApplicationDataRecoveryProgressCallback =
    void Function(ApplicationDataRecoveryProgress progress);

enum ApplicationDataRecoveryIssueKind {
  indexingImport,
  pendingImportFinalization,
  chapterSearchIndex,
  fileCleanup,
}

class ApplicationDataRecoveryIssue {
  final ApplicationDataRecoveryIssueKind kind;
  final int? bookId;
  final int? chapterId;
  final String? bookTitle;
  final String? chapterTitle;
  final Object error;
  final StackTrace stackTrace;

  const ApplicationDataRecoveryIssue({
    required this.kind,
    required this.error,
    required this.stackTrace,
    this.bookId,
    this.chapterId,
    this.bookTitle,
    this.chapterTitle,
  });

  bool get affectsSearch =>
      kind == ApplicationDataRecoveryIssueKind.indexingImport ||
      kind == ApplicationDataRecoveryIssueKind.chapterSearchIndex;
}

class ApplicationDataRecoveryReport {
  final List<ApplicationDataRecoveryIssue> issues;

  ApplicationDataRecoveryReport({
    List<ApplicationDataRecoveryIssue> issues = const [],
  }) : issues = List.unmodifiable(issues);

  bool get hasIssues => issues.isNotEmpty;

  bool get searchMayBeIncomplete => issues.any((issue) => issue.affectsSearch);

  int get failedChapterCount => issues
      .where(
        (issue) =>
            issue.kind == ApplicationDataRecoveryIssueKind.chapterSearchIndex,
      )
      .length;
}

Future<ApplicationDataRecoveryReport> recoverApplicationData(
  Database db, {
  BookStorage? storage,
  ApplicationDataRecoveryProgressCallback? onProgress,
}) {
  // 直接调用恢复 API 时也必须参与协调，避免只从界面入口调用才安全。
  return ApplicationDataOperationCoordinator.run(
    () => _recoverApplicationData(db, storage: storage, onProgress: onProgress),
  );
}

Future<ApplicationDataRecoveryReport> _recoverApplicationData(
  Database db, {
  BookStorage? storage,
  ApplicationDataRecoveryProgressCallback? onProgress,
}) async {
  final bookStorage = storage ?? BookStorage.shared;
  final issues = <ApplicationDataRecoveryIssue>[];

  await _resumeIndexingImports(db, bookStorage, issues, onProgress: onProgress);
  await _recoverPendingImports(db, bookStorage, issues, onProgress: onProgress);
  await _removeBrokenBooks(db, bookStorage, onProgress: onProgress);
  await _repairFtsIndex(db, bookStorage, issues, onProgress: onProgress);
  await _cleanupUnreferencedFiles(
    db,
    bookStorage,
    issues,
    onProgress: onProgress,
  );

  onProgress?.call(
    const ApplicationDataRecoveryProgress(
      phase: ApplicationDataRecoveryPhase.validatingDatabase,
      completed: 0,
      total: 0,
    ),
  );
  final violations = await db.rawQuery('PRAGMA foreign_key_check');
  if (violations.isNotEmpty) {
    throw StateError('启动完整性检查发现外键异常：$violations');
  }

  return ApplicationDataRecoveryReport(issues: issues);
}

Future<void> _resumeIndexingImports(
  Database db,
  BookStorage storage,
  List<ApplicationDataRecoveryIssue> issues, {
  ApplicationDataRecoveryProgressCallback? onProgress,
}) async {
  final jobs = await db.rawQuery('''
    SELECT job.book_id, job.staged_path, job.target_path, b.title AS book_title
    FROM import_jobs job
    JOIN books b ON b.id = job.book_id
    WHERE job.state = 'indexing'
    ORDER BY job.created_at
  ''');

  _notifyProgress(
    onProgress,
    phase: ApplicationDataRecoveryPhase.resumingImports,
    completed: 0,
    total: jobs.length,
  );
  for (var index = 0; index < jobs.length; index++) {
    final job = jobs[index];
    final bookId = job['book_id'] as int;
    final stagedPath = job['staged_path'] as String;
    final targetPath = job['target_path'] as String;
    final stagedExists = await storage.exists(stagedPath);
    final targetExists = await storage.exists(targetPath);

    if (!stagedExists && !targetExists) {
      // 索引中断且两侧文件都不存在，数据库半成品已经无法恢复。
      await deleteBookRecords(db, bookId);
      _notifyProgress(
        onProgress,
        phase: ApplicationDataRecoveryPhase.resumingImports,
        completed: index + 1,
        total: jobs.length,
      );
      continue;
    }

    final sourcePath = stagedExists ? stagedPath : targetPath;
    try {
      await indexPendingImport(
        db,
        bookId: bookId,
        readChapter: (chapter) => storage.readTextRange(
          sourcePath,
          startByte: chapter.startByte,
          endByte: chapter.endByte,
        ),
      );
    } catch (e, st) {
      // 当前任务暂时无法读取时保留 indexing 状态，下次启动继续补建，
      // 但必须把问题交给界面，避免用户误以为搜索已经完整。
      issues.add(
        ApplicationDataRecoveryIssue(
          kind: ApplicationDataRecoveryIssueKind.indexingImport,
          bookId: bookId,
          bookTitle: job['book_title'] as String?,
          error: e,
          stackTrace: st,
        ),
      );
    }
    _notifyProgress(
      onProgress,
      phase: ApplicationDataRecoveryPhase.resumingImports,
      completed: index + 1,
      total: jobs.length,
    );
  }
}

Future<void> _recoverPendingImports(
  Database db,
  BookStorage storage,
  List<ApplicationDataRecoveryIssue> issues, {
  ApplicationDataRecoveryProgressCallback? onProgress,
}) async {
  final jobs = await db.rawQuery('''
    SELECT job.book_id, job.staged_path, job.target_path, b.title AS book_title
    FROM import_jobs job
    JOIN books b ON b.id = job.book_id
    WHERE job.state = 'ready_to_finalize'
    ORDER BY job.created_at
  ''');

  _notifyProgress(
    onProgress,
    phase: ApplicationDataRecoveryPhase.finalizingImports,
    completed: 0,
    total: jobs.length,
  );
  for (var index = 0; index < jobs.length; index++) {
    final job = jobs[index];
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
      _notifyProgress(
        onProgress,
        phase: ApplicationDataRecoveryPhase.finalizingImports,
        completed: index + 1,
        total: jobs.length,
      );
      continue;
    }

    try {
      await storage.finalizeStagedFile(stagedFile);
      await db.delete('import_jobs', where: 'book_id = ?', whereArgs: [bookId]);
    } catch (e, st) {
      // 单个文件恢复失败时保留日志和临时文件，下次启动继续重试，
      // 同时让用户知道这本书仍未完成恢复。
      issues.add(
        ApplicationDataRecoveryIssue(
          kind: ApplicationDataRecoveryIssueKind.pendingImportFinalization,
          bookId: bookId,
          bookTitle: job['book_title'] as String?,
          error: e,
          stackTrace: st,
        ),
      );
    }
    _notifyProgress(
      onProgress,
      phase: ApplicationDataRecoveryPhase.finalizingImports,
      completed: index + 1,
      total: jobs.length,
    );
  }
}

Future<void> _removeBrokenBooks(
  Database db,
  BookStorage storage, {
  ApplicationDataRecoveryProgressCallback? onProgress,
}) async {
  _notifyProgress(
    onProgress,
    phase: ApplicationDataRecoveryPhase.checkingBooks,
    completed: 0,
    total: 0,
  );
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

Future<void> _repairFtsIndex(
  Database db,
  BookStorage storage,
  List<ApplicationDataRecoveryIssue> issues, {
  ApplicationDataRecoveryProgressCallback? onProgress,
}) async {
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

  // 缺失索引只能从规范化 UTF-8 文件的章节字节范围重新构建。
  final missingRows = await db.rawQuery('''
    SELECT
      c.id,
      c.book_id,
      c.title,
      c.start_byte,
      c.end_byte,
      b.file_path,
      b.title AS book_title
    FROM chapters c
    JOIN books b ON b.id = c.book_id
    LEFT JOIN chapters_fts f ON f.rowid = c.id
    WHERE f.rowid IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM import_jobs job WHERE job.book_id = b.id
      )
    ORDER BY b.id, c.chapter_index
  ''');
  _notifyProgress(
    onProgress,
    phase: ApplicationDataRecoveryPhase.rebuildingSearchIndex,
    completed: 0,
    total: missingRows.length,
  );
  final indexWorker = TextIndexWorker();
  try {
    for (var index = 0; index < missingRows.length; index++) {
      final row = missingRows[index];
      try {
        final startByte = row['start_byte'] as int;
        final endByte = row['end_byte'] as int;
        final content = await storage.readTextRange(
          row['file_path'] as String,
          startByte: startByte,
          endByte: endByte,
        );
        final tokens = await indexWorker.tokenize(
          title: row['title'] as String,
          content: content,
        );
        await db.insert('chapters_fts', {
          'rowid': row['id'],
          'title': tokens.title,
          'search': tokens.search,
        });
      } catch (e, st) {
        // 单章修复失败不阻止其它章节和界面启动，但记录下来让用户知道搜索不完整。
        issues.add(
          ApplicationDataRecoveryIssue(
            kind: ApplicationDataRecoveryIssueKind.chapterSearchIndex,
            bookId: row['book_id'] as int?,
            chapterId: row['id'] as int?,
            bookTitle: row['book_title'] as String?,
            chapterTitle: row['title'] as String?,
            error: e,
            stackTrace: st,
          ),
        );
      }
      _notifyProgress(
        onProgress,
        phase: ApplicationDataRecoveryPhase.rebuildingSearchIndex,
        completed: index + 1,
        total: missingRows.length,
      );
    }
  } finally {
    await indexWorker.close();
  }
}

Future<void> _cleanupUnreferencedFiles(
  Database db,
  BookStorage storage,
  List<ApplicationDataRecoveryIssue> issues, {
  ApplicationDataRecoveryProgressCallback? onProgress,
}) async {
  _notifyProgress(
    onProgress,
    phase: ApplicationDataRecoveryPhase.cleaningFiles,
    completed: 0,
    total: 0,
  );
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
  } catch (e, st) {
    // 文件残留不影响数据库一致性，保留到下次启动继续清理，但不要静默丢失原因。
    issues.add(
      ApplicationDataRecoveryIssue(
        kind: ApplicationDataRecoveryIssueKind.fileCleanup,
        error: e,
        stackTrace: st,
      ),
    );
  }
  try {
    await storage.deleteUnregisteredStagedFiles(registeredStagedFiles);
  } catch (e, st) {
    // 临时文件清理同样采用尽力而为策略，但把失败交给状态层。
    issues.add(
      ApplicationDataRecoveryIssue(
        kind: ApplicationDataRecoveryIssueKind.fileCleanup,
        error: e,
        stackTrace: st,
      ),
    );
  }
}

void _notifyProgress(
  ApplicationDataRecoveryProgressCallback? onProgress, {
  required ApplicationDataRecoveryPhase phase,
  required int completed,
  required int total,
}) {
  onProgress?.call(
    ApplicationDataRecoveryProgress(
      phase: phase,
      completed: completed,
      total: total,
    ),
  );
}
