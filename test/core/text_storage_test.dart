// 正文存储回归测试：验证 UTF-8 字节范围、Unicode 字符长度和旧数据回退。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/storage/book_storage.dart';

void main() {
  late Directory tempDirectory;
  late BookStorage storage;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('text_storage_');
    storage = BookStorage(rootProvider: () async => tempDirectory);
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('按 UTF-8 字节范围读取含中文和代理对的章节', () async {
    const text = '第一章🙂\n你好世界';
    final staged = await storage.stageTextFile(text);
    final chapter = '第一章🙂';
    final startByte = 0;
    final endByte = utf8.encode(chapter).length;

    expect(
      await storage.readTextRange(
        staged.stagedPath,
        startByte: startByte,
        endByte: endByte,
      ),
      chapter,
    );
    expect(
      await storage.readChapterText(
        staged.stagedPath,
        startChar: 0,
        endChar: chapter.length,
        startByte: startByte,
        endByte: endByte,
      ),
      chapter,
    );
  });

  test('分块读取在 UTF-8 多字节字符边界上仍保持完整文本', () async {
    const text = '甲🙂乙世界丙';
    final staged = await storage.stageTextFile(text);
    final chunks = <String>[];
    await for (final chunk in storage.readUtf8RangeChunks(
      staged.stagedPath,
      startByte: 0,
      endByte: utf8.encode(text).length,
      chunkBytes: 1,
    )) {
      chunks.add(chunk);
    }

    expect(chunks.join(), text);
  });

  test('缺少 UTF-8 字节范围时直接拒绝读取', () async {
    final staged = await storage.stageTextFile('你好世界');

    await expectLater(
      storage.readChapterText(
        staged.stagedPath,
        startChar: 0,
        endChar: 4,
        startByte: -1,
        endByte: -1,
      ),
      throwsStateError,
    );
  });
}
