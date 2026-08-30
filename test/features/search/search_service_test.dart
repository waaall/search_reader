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

    final result = await service.search('你好');
    final hits = result.hits;

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
      final result = await SearchService(
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
      final hit = result.hits;

      expect(hit, hasLength(1));
      expect(hit.single.charOffset, prefix.length);
      expect(hit.single.snippet, contains('<mark>搜索目标</mark>'));
      expect(hit.single.snippet.length, lessThan(200));
      expect(await storage.exists(staged.stagedPath), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('同一章节返回多个出现位置且英文定位不区分大小写', () async {
    const content = 'Alice 先出现，随后 ALICE 再出现。';
    final storage = _FakeBookStorage({1: content});
    final service = SearchService(
      dao: _FakeSearchDao([_row(bookId: 1, title: '书', content: content)]),
      storage: storage,
    );

    final result = await service.search('alice');

    expect(result.hits, hasLength(2));
    expect(result.hits.map((hit) => hit.charOffset), [
      content.indexOf('Alice'),
      content.indexOf('ALICE'),
    ]);
    expect(result.hits.every((hit) => hit.matchLength == 5), isTrue);
  });

  test('结果超过展示上限时截断并明确标记', () async {
    const content = '命中 命中 命中';
    final service = SearchService(
      dao: _FakeSearchDao([_row(bookId: 1, title: '书', content: content)]),
      storage: _FakeBookStorage({1: content}),
      resultLimit: 2,
    );

    final result = await service.search('命中');

    expect(result.hits, hasLength(2));
    expect(result.truncated, isTrue);
  });

  test('查询词跨文件块时仍返回一次正确命中', () async {
    const content = '前文Alice后文';
    final service = SearchService(
      dao: _FakeSearchDao([_row(bookId: 1, title: '书', content: content)]),
      storage: _FakeBookStorage({1: content}, chunkChars: 5),
    );

    final result = await service.search('alice');

    expect(result.hits, hasLength(1));
    expect(result.hits.single.charOffset, content.indexOf('Alice'));
    expect(result.hits.single.snippet, contains('<mark>Alice</mark>'));
  });

  test('仅命中章节标题时保留章节开头作为回退结果', () async {
    const content = '这段正文不包含查询词，只用于验证章节开头摘要。';
    final service = SearchService(
      dao: _FakeSearchDao([
        _row(bookId: 1, title: '书', chapterTitle: '搜索目标', content: content),
      ]),
      storage: _FakeBookStorage({1: content}, chunkChars: 5),
    );

    final result = await service.search('搜索目标');

    expect(result.hits, hasLength(1));
    expect(result.hits.single.chapterTitle, '搜索目标');
    expect(result.hits.single.charOffset, 0);
    expect(result.hits.single.matchLength, 0);
    expect(result.hits.single.snippet, startsWith('这段正文'));
    expect(result.hits.single.snippet, isNot(contains('<mark>')));
  });
}

ChapterMatchRow _row({
  required int bookId,
  required String title,
  required String content,
  String chapterTitle = '第一章',
  String? filePath,
}) {
  return ChapterMatchRow(
    bookId: bookId,
    bookTitle: title,
    bookFilePath: filePath ?? 'books/$bookId.txt',
    chapterId: bookId,
    chapterIndex: 0,
    chapterTitle: chapterTitle,
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
  _FakeBookStorage(this.contents, {this.beforeRead, this.chunkChars});

  final Map<int, String> contents;
  final Future<void> Function(int bookId)? beforeRead;
  final int? chunkChars;
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
    final content = contents[bookId]!;
    final size = chunkChars;
    if (size == null) {
      yield content;
      return;
    }
    for (var start = 0; start < content.length; start += size) {
      final end = (start + size).clamp(0, content.length);
      yield content.substring(start, end);
    }
  }
}
