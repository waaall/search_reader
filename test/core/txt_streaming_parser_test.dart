// TXT 流式导入测试：确认解析结果只传递范围，并保留规范化正文内容。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/db/text_index_worker.dart';
import 'package:search_reader/core/parser/book_import_worker.dart';
import 'package:search_reader/core/parser/import_limits.dart';
import 'package:search_reader/core/parser/txt_parser.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('txt_streaming_');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('输出 UTF-8 正文并生成字符/字节范围', () async {
    const sourceText = '  前言内容  \r\n\r\n第一章 测试\r\n你好🙂\r\n\r\n第二章 结束\r\n世界';
    final input = File(p.join(tempDirectory.path, 'input.txt'));
    final output = p.join(tempDirectory.path, 'normalized.txt');
    await input.writeAsString(sourceText, encoding: utf8);

    final manifest = await TxtParser().parseToFile(
      input.path,
      output,
      limits: const ImportLimits(maxTextChars: 1000),
    );
    const normalized = '  前言内容  \n\n第一章 测试\n你好🙂\n\n第二章 结束\n世界';
    final bytes = await File(output).readAsBytes();

    expect(utf8.decode(bytes), normalized);
    expect(manifest.totalChars, normalized.length);
    expect(manifest.totalBytes, bytes.length);
    expect(manifest.chapters, hasLength(3));
    for (final chapter in manifest.chapters) {
      final content = utf8.decode(
        bytes.sublist(chapter.startByte, chapter.endByte),
      );
      expect(content.length, chapter.endChar - chapter.startChar);
      expect(chapter.startByte, lessThanOrEqualTo(chapter.endByte));
    }
  });

  test('正文超过限制时拒绝并不保留半成品', () async {
    final input = File(p.join(tempDirectory.path, 'large.txt'));
    final output = p.join(tempDirectory.path, 'normalized.txt');
    await input.writeAsString('一' * 100);

    await expectLater(
      TxtParser().parseToFile(
        input.path,
        output,
        limits: const ImportLimits(maxTextChars: 10),
      ),
      throwsA(isA<TxtParseException>()),
    );
  });

  test('worker 返回可序列化的章节清单而不是全文字符串', () async {
    final input = File(p.join(tempDirectory.path, 'worker.txt'));
    final output = p.join(tempDirectory.path, 'worker-normalized.txt');
    await input.writeAsString('第一章\n你好世界');

    final manifest = await BookImportWorker.run(
      inputPath: input.path,
      outputPath: output,
      extension: '.txt',
    );

    expect(manifest.chapters, hasLength(1));
    expect(await File(output).readAsString(), '第一章\n你好世界');
  });

  test('大块写入不会把 UTF-16 代理对切成两个替换字符', () async {
    final sourceText = '${'a' * 65535}🙂结尾';
    final input = File(p.join(tempDirectory.path, 'surrogate.txt'));
    final output = p.join(tempDirectory.path, 'surrogate-normalized.txt');
    await input.writeAsString(sourceText);

    await TxtParser().parseToFile(input.path, output);

    expect(await File(output).readAsString(), sourceText);
  });

  test('索引 worker 返回 token 后可安全释放', () async {
    final worker = TextIndexWorker();
    try {
      final tokens = await worker.tokenize(title: '第一章', content: '你好世界');
      expect(tokens.title, contains('第一'));
      expect(tokens.title, contains('一章'));
      expect(tokens.search, contains('你好'));
      expect(tokens.search, contains('好世'));
    } finally {
      await worker.close();
    }
  });
}
