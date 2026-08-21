// 搜索服务回归测试：确认全库 FTS 命中后只读取章节范围，并串行处理请求。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/db/daos.dart';
import 'package:search_reader/core/storage/book_storage.dart';
import 'package:search_reader/features/search/search_service.dart';

void main() {
  test('多个书籍命中时不读取任何整本全文', () async {
    final rows = [
      _row(bookId: 1, title: '书一', content: '前文你好后文'),
      _row(bookId: 2, title: '书二', content: '另一处你好内容'),
    ];
    final storage = _FakeBookStorage({1: '前文你好后文', 2: '另一处你好内容'});
    final service = SearchService(dao: _FakeSearchDao(rows), storage: storage);

    final hits = await service.search('你好');

    expect(hits, hasLength(2));
    expect(storage.chapterReads, [1, 2]);
    expect(hits.first.snippet, contains('<mark>你好</mark>'));
  });

  test('新搜索等待旧搜索释放当前章节后再执行', () async {
    final firstReadStarted = Completer<void>();
    final releaseFirstRead = Completer<void>();
    final storage = _FakeBookStorage(
      {1: '你好内容'},
      beforeRead: (bookId) async {
        if (bookId == 1 && !firstReadStarted.isCompleted) {
          firstReadStarted.complete();
          await releaseFirstRead.future;
        }
      },
    );
    final service = SearchService(
      dao: _FakeSearchDao([_row(bookId: 1, title: '书', content: '你好内容')]),
      storage: storage,
    );

    final first = service.search('你好');
    await firstReadStarted.future;
    final second = service.search('你好');
    await Future<void>.delayed(Duration.zero);
    expect(storage.chapterReads, [1]);

    releaseFirstRead.complete();
    await first;
    await second;
    expect(storage.chapterReads, [1, 1]);
  });

  test('长章节只保留命中附近摘要并返回章节内全局偏移', () async {
    final directory = await Directory.systemTemp.createTemp('search_excerpt_');
    try {
      final storage = BookStorage(rootProvider: () async => directory);
      final prefix = '前文🙂' * 20000;
      final suffix = '后文' * 20000;
      final content = '$prefix搜索目标$suffix';
      final staged = await storage.stageTextFile(content);
      final hit = await SearchService(
        dao: _FakeSearchDao([
          _row(
            bookId: 1,
            title: '长书',
            content: content,
            filePath: staged.stagedPath,
          ),
        ]),
        storage: storage,
      ).search('搜索目标');

      expect(hit, hasLength(1));
      expect(hit.single.charOffset, prefix.length);
      expect(hit.single.snippet, contains('<mark>搜索目标</mark>'));
      expect(hit.single.snippet.length, lessThan(200));
      expect(await storage.exists(staged.stagedPath), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

ChapterMatchRow _row({
  required int bookId,
  required String title,
  required String content,
  String? filePath,
}) {
  return ChapterMatchRow(
    bookId: bookId,
    bookTitle: title,
    bookFilePath: filePath ?? 'books/$bookId.txt',
    chapterId: bookId,
    chapterIndex: 0,
    chapterTitle: '第一章',
    chapterStart: 0,
    chapterEnd: content.length,
    chapterStartByte: 0,
    chapterEndByte: utf8.encode(content).length,
  );
}

class _FakeSearchDao extends SearchDao {
  _FakeSearchDao(this.rows);

  final List<ChapterMatchRow> rows;

  @override
  Future<List<ChapterMatchRow>> queryMatches(
    String ftsQuery, {
    int limit = 100,
  }) async {
    return rows.take(limit).toList(growable: false);
  }
}

class _FakeBookStorage extends BookStorage {
  _FakeBookStorage(this.contents, {this.beforeRead});

  final Map<int, String> contents;
  final Future<void> Function(int bookId)? beforeRead;
  final List<int> chapterReads = [];

  @override
  Stream<String> readUtf8RangeChunks(
    String relativePath, {
    required int startByte,
    required int endByte,
    int chunkBytes = 64 * 1024,
  }) async* {
    final bookId = int.parse(relativePath.split('/').last.split('.').first);
    chapterReads.add(bookId);
    await beforeRead?.call(bookId);
    yield contents[bookId]!;
  }
}
