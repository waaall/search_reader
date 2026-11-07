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

  for (final prefix in ['', '前缀🙂']) {
    for (final text in [
      '',
      '\uFEFF',
      '\uFEFF\uFEFF正文🙂',
      '甲\uFEFF乙',
      '\uFEFE正文',
    ]) {
      test('范围读取保留正文字符：前缀 ${prefix.length}，正文 ${jsonEncode(text)}', () async {
        final staged = await storage.stageTextFile('$prefix$text');
        final startByte = utf8.encode(prefix).length;
        final endByte = startByte + utf8.encode(text).length;
        expect(
          await storage.readChapterText(
            staged.stagedPath,
            startChar: 0,
            endChar: text.length,
            startByte: startByte,
            endByte: endByte,
          ),
          text,
        );
        // BOM 的三个字节被拆进不同块时，流式读取也不能遗漏正文字符。
        for (final chunkBytes in [1, 2, 3, 4, 7]) {
          expect(
            await storage
                .readUtf8RangeChunks(
                  staged.stagedPath,
                  startByte: startByte,
                  endByte: endByte,
                  chunkBytes: chunkBytes,
                )
                .join(),
            text,
          );
        }
      });
    }
  }

  for (final bytes in [
    [0xEF],
    [0xEF, 0xBB],
    [0xEF, 0xBB, 0xBF, 0xFF],
  ]) {
    test('保留正文 U+FEFF 时仍严格拒绝无效 UTF-8：$bytes', () async {
      final staged = await storage.allocateNormalizedStagedFile();
      await File(
        await storage.resolveAbsolute(staged.stagedPath),
      ).writeAsBytes(bytes);
      await expectLater(
        storage.readTextRange(
          staged.stagedPath,
          startByte: 0,
          endByte: bytes.length,
        ),
        throwsFormatException,
      );
      await expectLater(
        storage
            .readUtf8RangeChunks(
              staged.stagedPath,
              startByte: 0,
              endByte: bytes.length,
              chunkBytes: 1,
            )
            .join(),
        throwsFormatException,
      );
    });
  }

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

  test('文件状态区分普通文件、明确缺失和非普通路径', () async {
    final staged = await storage.stageTextFile('正文');
    expect(
      await storage.inspectAvailability(staged.stagedPath),
      BookFileAvailability.available,
    );
    expect(
      await storage.inspectAvailability('books/missing.txt'),
      BookFileAvailability.missing,
    );
    expect(
      await storage.inspectAvailability('books/.staging'),
      BookFileAvailability.unavailable,
    );
    expect(
      await storage.inspectAvailability('../outside.txt'),
      BookFileAvailability.unavailable,
    );
  });

  test('符号链接不作为普通正文文件清理', () async {
    final staged = await storage.stageTextFile('正文');
    final target = await storage.resolveAbsolute(staged.stagedPath);
    final link = await storage.resolveAbsolute('books/linked.txt');
    await Link(link).create(target);
    expect(
      await storage.inspectAvailability('books/linked.txt'),
      BookFileAvailability.unavailable,
    );
  }, skip: Platform.isWindows);
}
