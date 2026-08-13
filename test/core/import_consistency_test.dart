// 导入崩溃一致性测试：验证数据库原子提交、临时文件发布和启动恢复。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/db/application_data_recovery.dart';
import 'package:search_reader/core/db/daos.dart';
import 'package:search_reader/core/db/database_schema.dart';
import 'package:search_reader/core/db/text_index.dart';
import 'package:search_reader/core/parser/book_format.dart';
import 'package:search_reader/core/storage/book_storage.dart';
import 'package:search_reader/features/library/book_deletion_service.dart';
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

  test('书籍、章节、FTS 和导入日志在同一事务内提交', () async {
    final staged = await storage.stageTextFile(_content);
    final book = await importDao.createPendingImport(
      title: '测试书籍',
      stagedPath: staged.stagedPath,
      targetPath: staged.targetPath,
      parsed: _parsedBook(),
    );

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

  test('章节或 FTS 写入失败时回滚整本书', () async {
    final staged = await storage.stageTextFile(_content);
    await database.execute('DROP TABLE chapters_fts');

    await expectLater(
      importDao.createPendingImport(
        title: '应回滚',
        stagedPath: staged.stagedPath,
        targetPath: staged.targetPath,
        parsed: _parsedBook(),
      ),
      throwsA(anything),
    );

    expect(await database.query('books'), isEmpty);
    expect(await database.query('chapters'), isEmpty);
    expect(await database.query('import_jobs'), isEmpty);
  });

  test('启动时完成数据库已提交但文件尚未发布的导入', () async {
    final staged = await storage.stageTextFile(_content);
    await importDao.createPendingImport(
      title: '待恢复',
      stagedPath: staged.stagedPath,
      targetPath: staged.targetPath,
      parsed: _parsedBook(),
    );

    await recoverApplicationData(database, storage: storage);

    expect(await storage.exists(staged.stagedPath), isFalse);
    expect(await storage.exists(staged.targetPath), isTrue);
    expect(await database.query('import_jobs'), isEmpty);
    expect(await BookDao(database: database).listAll(), hasLength(1));
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
    final staged = await storage.stageTextFile(_content);
    final book = await importDao.createPendingImport(
      title: '暂时无法检查',
      stagedPath: staged.stagedPath,
      targetPath: staged.targetPath,
      parsed: _parsedBook(),
    );
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
    final staged = await storage.stageTextFile(_content);
    final book = await importDao.createPendingImport(
      title: '文件已丢失',
      stagedPath: staged.stagedPath,
      targetPath: staged.targetPath,
      parsed: _parsedBook(),
    );
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
    final staged = await storage.stageTextFile(_content);
    final book = await importDao.createPendingImport(
      title: '修复索引',
      stagedPath: staged.stagedPath,
      targetPath: staged.targetPath,
      parsed: _parsedBook(),
    );
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

  test('数据库删除成功后文件失败不误报，并由启动清理重试', () async {
    final staged = await storage.stageTextFile(_content);
    final book = await importDao.createPendingImport(
      title: '待删除',
      stagedPath: staged.stagedPath,
      targetPath: staged.targetPath,
      parsed: _parsedBook(),
    );
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

ParsedBook _parsedBook() {
  return const ParsedBook(
    fullText: _content,
    encoding: 'utf-8',
    chapters: [
      ParsedChapter(
        title: '第一章',
        startChar: 0,
        endChar: _content.length,
        content: _content,
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
