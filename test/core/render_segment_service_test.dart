// 旧书分片补建测试：确认首次打开流式生成范围、并发调用复用同一任务且正文可还原。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/db/daos.dart';
import 'package:search_reader/core/db/database_schema.dart';
import 'package:search_reader/core/db/render_segment_service.dart';
import 'package:search_reader/core/parser/render_segmenter.dart';
import 'package:search_reader/core/parser/book_format.dart';
import 'package:search_reader/core/storage/book_storage.dart';
import 'package:search_reader/domain/book.dart';
import 'package:search_reader/domain/chapter.dart';
import 'package:search_reader/domain/render_segment.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('派生缓存查询和写入均失败时仍返回有效的内存分片', () async {
    const text = '正文🙂内容';
    final chapter = Chapter(
      id: 1,
      bookId: 1,
      chapterIndex: 0,
      title: '正文',
      startChar: 0,
      endChar: text.length,
      startByte: 0,
      endByte: utf8.encode(text).length,
    );
    final book = Book(
      id: 1,
      title: '测试书',
      filePath: 'books/test.txt',
      encoding: 'utf-8',
      totalChars: text.length,
      createdAt: DateTime(2026),
    );
    final dao = _UnavailableSegmentDao();
    final service = RenderSegmentService(dao: dao, storage: _TextStorage(text));
    final segments = await service.ensureForChapter(book, chapter);
    expect(segments.single.startChar, chapter.startChar);
    expect(segments.single.endChar, chapter.endChar);
    expect(segments.single.endByte, chapter.endByte);
    expect(segments.single.id, isNegative);
    expect(dao.writeAttempts, 1);
    // 当前调用结束后释放并发任务，下一次仍有机会补写缓存，不能永久缓存失败状态。
    await service.ensureForChapter(book, chapter);
    expect(dao.writeAttempts, 2);
  });

  test('首次打开旧章节时补建连续分片且无需重新导入', () async {
    final root = await Directory.systemTemp.createTemp('segment_backfill_');
    final dbPath = p.join(root.path, 'test.db');
    final database = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: DatabaseSchema.version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => DatabaseSchema.create(db),
      ),
    );
    try {
      final content = List.generate(30, (index) => '零碎段落$index\n').join();
      final relativePath = p.join('books', 'old.txt');
      final file = File(p.join(root.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      final byteCount = utf8.encode(content).length;

      final bookId = await database.insert('books', {
        'title': '旧书',
        'file_path': relativePath,
        'encoding': 'utf-8',
        'total_chars': content.length,
        'created_at': 1,
      });
      final chapterId = await database.insert('chapters', {
        'book_id': bookId,
        'chapter_index': 0,
        'title': '正文',
        'start_char': 0,
        'end_char': content.length,
        'start_byte': 0,
        'end_byte': byteCount,
      });
      final book = Book(
        id: bookId,
        title: '旧书',
        filePath: relativePath,
        encoding: 'utf-8',
        totalChars: content.length,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      );
      final chapter = Chapter(
        id: chapterId,
        bookId: bookId,
        chapterIndex: 0,
        title: '正文',
        startChar: 0,
        endChar: content.length,
        startByte: 0,
        endByte: byteCount,
      );
      final storage = BookStorage(rootProvider: () async => root);
      final service = RenderSegmentService(
        dao: RenderSegmentDao(database: database),
        storage: storage,
        builder: const StreamingRenderSegmentBuilder(
          segmenter: RenderSegmenter(
            policy: ReaderRenderPolicy(
              targetChars: 30,
              maxChars: 45,
              minNaturalBoundaryChars: 15,
            ),
          ),
        ),
      );

      final results = await Future.wait([
        service.ensureForChapter(book, chapter),
        service.ensureForChapter(book, chapter),
      ]);
      final segments = results.first;
      expect(segments.length, greaterThan(1));
      expect(
        await database.query('render_segments'),
        hasLength(segments.length),
      );

      final restored = StringBuffer();
      for (final segment in segments) {
        restored.write(
          await storage.readTextRange(
            relativePath,
            startByte: segment.startByte,
            endByte: segment.endByte,
          ),
        );
      }
      expect(restored.toString(), content);
    } finally {
      await database.close();
      await databaseFactoryFfi.deleteDatabase(dbPath);
      await root.delete(recursive: true);
    }
  });
}

class _UnavailableSegmentDao extends RenderSegmentDao {
  int writeAttempts = 0;

  @override
  Future<List<RenderSegment>> listByChapter(int chapterId) async {
    throw StateError('模拟缓存查询失败');
  }

  @override
  Future<void> replaceChapterSegments(
    int chapterId,
    List<RenderSegmentDescriptor> segments,
  ) async {
    writeAttempts++;
    throw StateError('模拟缓存写入失败');
  }
}

class _TextStorage extends BookStorage {
  final String text;
  _TextStorage(this.text);

  @override
  Stream<String> readUtf8RangeChunks(
    String relativePath, {
    required int startByte,
    required int endByte,
    int chunkBytes = 64 * 1024,
  }) => Stream.value(text);
}
