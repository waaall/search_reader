import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/parser/txt_parser.dart';

void main() {
  group('TxtParser', () {
    late Directory tempDir;
    late TxtParser parser;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('parser_test_');
      parser = TxtParser();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<String> writeTxt(String name, String content) async {
      final f = File(p.join(tempDir.path, name));
      await f.writeAsString(content);
      return f.path;
    }

    test('识别中文章节标题', () async {
      final path = await writeTxt('book.txt', '''
第一章 楚云天

夜已深，寒风裹着雪粒。

第二章 论剑

他迈步走出客栈。

第三章 暗流

朝阳初升时，城门外人声鼎沸。
''');
      final book = await parser.parse(path);
      expect(book.chapters.length, 3);
      expect(book.chapters[0].title, contains('第一章'));
      expect(book.chapters[1].title, contains('第二章'));
      expect(book.chapters[2].title, contains('第三章'));
    });

    test('识别楔子/序章等特殊标题', () async {
      final path = await writeTxt('book.txt', '''
楔子

故事的开端。

第一章 起

主角登场。
''');
      final book = await parser.parse(path);
      expect(book.chapters.length, 2);
      expect(book.chapters[0].title, contains('楔子'));
    });

    test('无章节标题时整本作为单章', () async {
      final path = await writeTxt('book.txt', '这只是一段普通文字\n没有任何章节标记。');
      final book = await parser.parse(path);
      expect(book.chapters.length, 1);
      expect(book.chapters[0].title, '正文');
    });

    test('章节起止位置可正确还原原文', () async {
      const text = '第一章 测试\n\n这是第一章的内容。\n\n第二章 验证\n\n这是第二章的内容。';
      final path = await writeTxt('book.txt', text);
      final book = await parser.parse(path);
      // 用起止位置切片应该能还原各章节
      for (final c in book.chapters) {
        final slice = book.fullText.substring(c.startChar, c.endChar);
        expect(slice.length, c.endChar - c.startChar);
      }
    });
  });
}
