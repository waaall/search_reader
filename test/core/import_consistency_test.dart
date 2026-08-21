// 导入一致性测试：验证短事务、分批索引、临时文件发布和启动恢复。
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/db/application_data_recovery.dart';
import 'package:search_reader/core/db/daos.dart';
import 'package:search_reader/core/db/database_schema.dart';
import 'package:search_reader/core/db/text_index.dart';
import 'package:search_reader/core/parser/book_format.dart';
import 'package:search_reader/core/storage/book_storage.dart';
import 'package:search_reader/domain/book.dart';
import 'package:search_reader/features/library/book_deletion_service.dart';
import 'package:search_reader/features/importer/importer_service.dart';
import 'package:search_reader/features/search/search_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _content = '第一章\n你好世界';

void main() {
  late Directory tempDirectory;
  late Database database;
  late BookStorage storage;
  late BookImportDao importDao;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'search_reader_consistency_',
    );
    storage = BookStorage(rootProvider: () async => tempDirectory);
    database = await databaseFactoryFfi.openDatabase(
      p.join(tempDirectory.path, 'test.db'),
      options: OpenDatabaseOptions(
        version: DatabaseSchema.version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => DatabaseSchema.create(db),
      ),
    );
    importDao = BookImportDao(database: database);
  });

  tearDown(() async {
    await database.close();
    await tempDirectory.delete(recursive: true);
  });

  test('元数据和分批 FTS 写入完成后保留待发布日志', () async {
    final pending = await _createPendingImport(
      title: '测试书籍',
      content: _content,
      storage: storage,
      importDao: importDao,
    );
    final staged = pending.staged;
    final book = pending.book;

    expect(await database.query('books'), hasLength(1));
    expect(await database.query('chapters'), hasLength(1));
    expect(await database.query('chapters_fts'), hasLength(1));
    expect(await database.query('import_jobs'), hasLength(1));
    expect(await BookDao(database: database).listAll(), isEmpty);

    await storage.finalizeStagedFile(staged);
    await importDao.markImportComplete(book.id);

    expect(await storage.exists(staged.stagedPath), isFalse);
    expect(await storage.exists(staged.targetPath), isTrue);
    expect(await BookDao(database: database).listAll(), hasLength(1));
  });

  test('规范化正文导入保存字节范围并保持全文 FTS', () async {
    const content = '第一章🙂\n你好世界';
    final staged = await storage.stageTextFile(content);
    final chapterEnd = utf8.encode(content).length;
    final manifest = BookImportManifest(
      encoding: 'utf-8',
      totalChars: content.length,
      totalBytes: chapterEnd,
      chapters: [
        ChapterDescriptor(
          title: '第一章',
          startChar: 0,
          endChar: content.length,
          startByte: 0,
          endByte: chapterEnd,
        ),
      ],
    );

    final book = await importDao.createPendingImportFromManifest(
      title: '规范化正文',
      stagedPath: staged.stagedPath,
      targetPath: staged.targetPath,
      manifest: manifest,
      readChapter: (chapter) => storage.readTextRange(
        staged.stagedPath,
        startByte: chapter.startByte,
        endByte: chapter.endByte,
      ),
    );

    final chapter = (await database.query('chapters')).single;
    expect(chapter['start_byte'], 0);
    expect(chapter['end_byte'], chapterEnd);
    expect(
      await database.rawQuery(
        'SELECT rowid FROM chapters_fts WHERE chapters_fts MATCH ?',
        [toBigramQuery('你好')],
      ),
      hasLength(1),
    );
    expect(book.totalChars, content.length);
  });

  test('ImporterService 通过 worker 导入 TXT 后可按范围阅读和全文搜索', () async {
    final source = File(p.join(tempDirectory.path, 'worker-book.txt'));
    await source.writeAsString('第一章\n你好世界\n第二章\n搜索目标');
    final service = ImporterService(importDao: importDao, storage: storage);

    final result = await service.importFile(source.path);
    final book = (await BookDao(database: database).listAll()).single;
    final chapters = await database.query(
      'chapters',
      orderBy: 'chapter_index ASC',
    );

    expect(result.bookId, book.id);
    expect(book.filePath, endsWith('.txt'));
    expect(chapters, hasLength(2));
    expect(chapters.first['start_byte'], 0);
    expect(
      await database.rawQuery(
        'SELECT rowid FROM chapters_fts WHERE chapters_fts MATCH ?',
        [toBigramQuery('搜索目标')],
      ),
      hasLength(1),
    );
    final hits = await SearchService(
      dao: SearchDao(database: database),
      storage: storage,
    ).search('搜索目标');
    expect(hits, hasLength(1));
    expect(hits.single.snippet, contains('<mark>搜索目标</mark>'));
    expect(
      await storage.readChapterText(
        book.filePath,
        startChar: chapters.last['start_char']! as int,
        endChar: chapters.last['end_char']! as int,
        startByte: chapters.last['start_byte']! as int,
        endByte: chapters.last['end_byte']! as int,
      ),
      contains('搜索目标'),
    );
  });

  test('索引处理失败时回滚整本书', () async {
    final staged = await storage.stageTextFile(_content);
    await expectLater(
      importDao.createPendingImportFromManifest(
        title: '应回滚',
        stagedPath: staged.stagedPath,
        targetPath: staged.targetPath,
        manifest: _manifestFor(_content),
        readChapter: (_) =>
            Future<String>.error(const FileSystemException('模拟章节读取失败')),
      ),
      throwsA(anything),
    );

    expect(await database.query('books'), isEmpty);
    expect(await database.query('chapters'), isEmpty);
    expect(await database.query('import_jobs'), isEmpty);
  });

  test('启动时完成数据库已提交但文件尚未发布的导入', () async {
    final pending = await _createPendingImport(
      title: '待恢复',
      content: _content,
      storage: storage,
      importDao: importDao,
    );
    final staged = pending.staged;

    await recoverApplicationData(database, storage: storage);

    expect(await storage.exists(staged.stagedPath), isFalse);
    expect(await storage.exists(staged.targetPath), isTrue);
    expect(await database.query('import_jobs'), isEmpty);
    expect(await BookDao(database: database).listAll(), hasLength(1));
  });

  test('启动时恢复索引中断的导入并继续发布', () async {
    final staged = await storage.stageTextFile(_content);
    final bookId = await database.insert('books', {
      'title': '索引中断',
      'author': null,
      'file_path': staged.targetPath,
      'encoding': 'utf-8',
      'total_chars': _content.length,
      'created_at': 1,
      'last_read_at': null,
    });
    final bytes = utf8.encode(_content).length;
    await database.insert('chapters', {
      'book_id': bookId,
      'chapter_index': 0,
      'title': '第一章',
      'start_char': 0,
      'end_char': _content.length,
      'start_byte': 0,
      'end_byte': bytes,
    });
    await database.insert('import_jobs', {
      'book_id': bookId,
      'staged_path': staged.stagedPath,
      'target_path': staged.targetPath,
      'state': 'indexing',
      'created_at': 1,
    });

    await recoverApplicationData(database, storage: storage);

    expect(
      await database.rawQuery(
        'SELECT rowid FROM chapters_fts WHERE chapters_fts MATCH ?',
        [toBigramQuery('你好')],
      ),
      hasLength(1),
    );
    expect(await database.query('import_jobs'), isEmpty);
    expect(await storage.exists(staged.stagedPath), isFalse);
    expect(await storage.exists(staged.targetPath), isTrue);
    expect(await BookDao(database: database).listAll(), hasLength(1));
  });

  test('索引读文件期间不长时间占用数据库事务', () async {
    final staged = await storage.stageTextFile(_content);
    final readStarted = Completer<void>();
    final releaseRead = Completer<void>();
    final pendingImport = importDao.createPendingImportFromManifest(
      title: '短事务',
      stagedPath: staged.stagedPath,
      targetPath: staged.targetPath,
      manifest: _manifestFor(_content),
      readChapter: (chapter) async {
        if (!readStarted.isCompleted) readStarted.complete();
        await releaseRead.future;
        return storage.readTextRange(
          staged.stagedPath,
          startByte: chapter.startByte,
          endByte: chapter.endByte,
        );
      },
    );

    try {
      await readStarted.future.timeout(const Duration(seconds: 2));
      expect(
        await BookDao(database: database)
            .listAll()
            .timeout(const Duration(seconds: 2)),
        isEmpty,
      );
    } finally {
      if (!releaseRead.isCompleted) releaseRead.complete();
      await pendingImport;
    }
  });

  test('启动时清理无日志临时文件、坏书和孤儿正式文件', () async {
    final unregistered = await storage.stageTextFile('未登记');
    final brokenFile = await storage.stageTextFile('坏书');
    await storage.finalizeStagedFile(brokenFile);
    final orphanFile = await storage.stageTextFile('孤儿');
    await storage.finalizeStagedFile(orphanFile);

    await database.insert('books', {
      'title': '没有章节的坏书',
      'author': null,
      'file_path': brokenFile.targetPath,
      'encoding': 'utf-8',
      'total_chars': 2,
      'created_at': 1,
      'last_read_at': null,
    });

    await recoverApplicationData(database, storage: storage);

    expect(await database.query('books'), isEmpty);
    expect(await storage.exists(unregistered.stagedPath), isFalse);
    expect(await storage.exists(brokenFile.targetPath), isFalse);
    expect(await storage.exists(orphanFile.targetPath), isFalse);
  });

  test('文件状态无法确认时保留书籍数据并继续恢复', () async {
    final pending = await _createPendingImport(
      title: '暂时无法检查',
      content: _content,
      storage: storage,
      importDao: importDao,
    );
    final staged = pending.staged;
    final book = pending.book;
    await storage.finalizeStagedFile(staged);
    await importDao.markImportComplete(book.id);

    final unavailableStorage = _UnavailableInspectionStorage(
      rootProvider: () async => tempDirectory,
    );
    await recoverApplicationData(database, storage: unavailableStorage);

    expect(
      await database.query('books', where: 'id = ?', whereArgs: [book.id]),
      hasLength(1),
    );
    expect(await database.query('chapters'), hasLength(1));
    expect(await storage.exists(staged.targetPath), isTrue);
  });

  test('文件明确不存在时仍会清理损坏的书籍记录', () async {
    final pending = await _createPendingImport(
      title: '文件已丢失',
      content: _content,
      storage: storage,
      importDao: importDao,
    );
    final staged = pending.staged;
    final book = pending.book;
    await storage.finalizeStagedFile(staged);
    await importDao.markImportComplete(book.id);
    await storage.deleteFile(staged.targetPath);

    await recoverApplicationData(database, storage: storage);

    expect(
      await database.query('books', where: 'id = ?', whereArgs: [book.id]),
      isEmpty,
    );
    expect(await database.query('chapters'), isEmpty);
  });

  test('非法书籍路径不会阻断启动或删除用户数据', () async {
    final bookId = await database.insert('books', {
      'title': '路径异常但保留',
      'author': null,
      'file_path': '../outside.txt',
      'encoding': 'utf-8',
      'total_chars': _content.length,
      'created_at': 1,
      'last_read_at': null,
    });
    final chapterId = await database.insert('chapters', {
      'book_id': bookId,
      'chapter_index': 0,
      'title': '第一章',
      'start_char': 0,
      'end_char': _content.length,
      'start_byte': 0,
      'end_byte': utf8.encode(_content).length,
    });
    await database.insert('chapters_fts', {
      'rowid': chapterId,
      'title': toBigramTokens('第一章'),
      'search': toBigramTokens(_content),
    });

    await expectLater(
      recoverApplicationData(database, storage: storage),
      completes,
    );

    expect(
      await database.query('books', where: 'id = ?', whereArgs: [bookId]),
      hasLength(1),
    );
  });

  test('启动时根据正式文件补建缺失的 FTS 行', () async {
    final pending = await _createPendingImport(
      title: '修复索引',
      content: _content,
      storage: storage,
      importDao: importDao,
    );
    final staged = pending.staged;
    final book = pending.book;
    await storage.finalizeStagedFile(staged);
    await importDao.markImportComplete(book.id);
    await database.delete('chapters_fts');

    await recoverApplicationData(database, storage: storage);

    final matches = await database.rawQuery(
      'SELECT rowid FROM chapters_fts WHERE chapters_fts MATCH ?',
      [toBigramQuery('你好')],
    );
    expect(matches, hasLength(1));
  });

  test('单章 FTS 修复失败时返回可展示的搜索不完整状态', () async {
    final pending = await _createPendingImport(
      title: '部分索引失败',
      content: _content,
      storage: storage,
      importDao: importDao,
    );
    final staged = pending.staged;
    final book = pending.book;
    await storage.finalizeStagedFile(staged);
    await importDao.markImportComplete(book.id);
    await database.delete('chapters_fts');

    final report = await recoverApplicationData(
      database,
      storage: _FailingReadStorage(rootProvider: () async => tempDirectory),
    );

    expect(report.searchMayBeIncomplete, isTrue);
    expect(report.failedChapterCount, 1);
    expect(report.issues.single.chapterId, isNotNull);
    expect(await database.query('chapters_fts'), isEmpty);
  });

  test('数据库删除成功后文件失败不误报，并由启动清理重试', () async {
    final pending = await _createPendingImport(
      title: '待删除',
      content: _content,
      storage: storage,
      importDao: importDao,
    );
    final staged = pending.staged;
    final book = pending.book;
    await storage.finalizeStagedFile(staged);
    await importDao.markImportComplete(book.id);

    final failingStorage = _FailingDeletionStorage(
      rootProvider: () async => tempDirectory,
    );
    final service = BookDeletionService(
      bookDao: BookDao(database: database),
      storage: failingStorage,
    );
    await expectLater(service.delete(book), completes);

    expect(await database.query('books'), isEmpty);
    expect(await storage.exists(staged.targetPath), isTrue);

    await recoverApplicationData(database, storage: storage);
    expect(await storage.exists(staged.targetPath), isFalse);
  });
}

class _PendingImport {
  final StagedBookFile staged;
  final Book book;

  const _PendingImport({required this.staged, required this.book});
}

Future<_PendingImport> _createPendingImport({
  required String title,
  required String content,
  required BookStorage storage,
  required BookImportDao importDao,
}) async {
  final staged = await storage.stageTextFile(content);
  final book = await importDao.createPendingImportFromManifest(
    title: title,
    stagedPath: staged.stagedPath,
    targetPath: staged.targetPath,
    manifest: _manifestFor(content),
    readChapter: (chapter) => storage.readTextRange(
      staged.stagedPath,
      startByte: chapter.startByte,
      endByte: chapter.endByte,
    ),
  );
  return _PendingImport(staged: staged, book: book);
}

BookImportManifest _manifestFor(String content) {
  final bytes = utf8.encode(content).length;
  return BookImportManifest(
    encoding: 'utf-8',
    totalChars: content.length,
    totalBytes: bytes,
    chapters: [
      ChapterDescriptor(
        title: '第一章',
        startChar: 0,
        endChar: content.length,
        startByte: 0,
        endByte: bytes,
      ),
    ],
  );
}

class _FailingDeletionStorage extends BookStorage {
  _FailingDeletionStorage({required super.rootProvider});

  @override
  Future<void> deleteFile(String relativePath) {
    throw const FileSystemException('模拟文件删除失败');
  }
}

class _UnavailableInspectionStorage extends BookStorage {
  _UnavailableInspectionStorage({required super.rootProvider});

  @override
  Future<BookFileAvailability> inspectAvailability(String relativePath) async {
    return BookFileAvailability.unavailable;
  }
}

class _FailingReadStorage extends BookStorage {
  _FailingReadStorage({required super.rootProvider});

  @override
  Future<String> readTextRange(
    String relativePath, {
    required int startByte,
    required int endByte,
  }) {
    return Future<String>.error(const FileSystemException('模拟章节读取失败'));
  }
}
