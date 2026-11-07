// 阅读降级回归：可读正文不依赖附属写入成功，但真实的范围损坏仍必须报错。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/db/daos.dart';
import 'package:search_reader/core/parser/render_segmenter.dart';
import 'package:search_reader/features/reader/reader_provider.dart';

import '../../support/application_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApplicationFixture fixture;
  setUp(() async {
    fixture = ApplicationFixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());

  for (final missingCache in [false, true]) {
    test('正文 U+FEFF 落在分片开头仍可完整阅读，缺少缓存：$missingCache', () async {
      const target = ReaderRenderPolicy.defaultTargetChars;
      final text = '${'a' * (target - 1)}\n\uFEFF${'正文🙂' * target}';
      final imported = await fixture.importBytes(
        'boundary.txt',
        utf8.encode(text),
      );
      if (missingCache) await fixture.db.delete('render_segments');
      final container = ProviderContainer();
      final provider = readerProvider(imported.bookId);
      final sub = container.listen(provider, (_, _) {});
      try {
        final reader = await container.read(provider.future);
        expect(reader.currentChapterSegments[1].startChar, target);
        final notifier = container.read(provider.notifier);
        final parts = <String>[];
        for (
          var index = 0;
          index < reader.currentChapterSegments.length;
          index++
        ) {
          parts.add(await notifier.readSegmentText(index));
        }
        expect(parts[1], startsWith('\uFEFF'));
        expect(parts.join(), text);
        await notifier.saveProgress(target);
        container.invalidate(provider);
        final reopened = await container.read(provider.future);
        expect(reopened.initialSegmentIndex, 1);
        expect(reopened.initialSegmentText, parts[1]);
      } finally {
        sub.close();
        container.dispose();
      }
    });
  }

  for (final missingCache in [false, true]) {
    test('数据库只读仍能打开正文，缺少分片缓存：$missingCache', () async {
      const text = '第一章\n正文完好🙂';
      final imported = await fixture.importBytes('book.txt', utf8.encode(text));
      if (missingCache) await fixture.db.delete('render_segments');
      await fixture.db.execute('PRAGMA query_only = ON');
      final container = ProviderContainer();
      final sub = container.listen(readerProvider(imported.bookId), (_, _) {});
      try {
        final reader = await container.read(
          readerProvider(imported.bookId).future,
        );
        expect(reader.initialSegmentText, text);
        expect(reader.currentChapterSegments, isNotEmpty);
        expect(
          (await fixture.db.query('books')).single['last_read_at'],
          isNull,
        );
        if (missingCache) {
          expect(await fixture.db.query('render_segments'), isEmpty);
          expect(reader.currentChapterSegments.single.id, isNegative);
        }
        final notifier = container.read(
          readerProvider(imported.bookId).notifier,
        );
        await expectLater(notifier.saveProgress(4), completes);
        expect(
          container
              .read(readerProvider(imported.bookId))
              .requireValue
              .initialCharOffset,
          4,
        );
        expect(await fixture.db.query('reading_progress'), isEmpty);
        // 下一次数据库恢复可写后，正常打开仍会重新尝试附属写入。
        await fixture.db.execute('PRAGMA query_only = OFF');
        await notifier.saveProgress(6);
        expect(
          (await fixture.db.query('reading_progress')).single['char_offset'],
          6,
        );
        container.invalidate(readerProvider(imported.bookId));
        await container.read(readerProvider(imported.bookId).future);
        expect(
          (await fixture.db.query('books')).single['last_read_at'],
          isNotNull,
        );
        expect(await fixture.db.query('render_segments'), isNotEmpty);
      } finally {
        sub.close();
        container.dispose();
        await fixture.db.execute('PRAGMA query_only = OFF');
      }
    });
  }

  test('缓存落库失败不能掩盖正文与字符范围不一致', () async {
    final imported = await fixture.importBytes('book.txt', utf8.encode('正文完好'));
    await fixture.db.delete('render_segments');
    final chapter = (await ChapterDao().listByBook(imported.bookId)).single;
    await fixture.db.update(
      'chapters',
      {'end_char': chapter.endChar + 1},
      where: 'id = ?',
      whereArgs: [chapter.id],
    );
    await fixture.db.execute('PRAGMA query_only = ON');
    final container = ProviderContainer();
    final sub = container.listen(readerProvider(imported.bookId), (_, _) {});
    try {
      await expectLater(
        container.read(readerProvider(imported.bookId).future),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            '范围错误',
            contains('范围与章节不一致'),
          ),
        ),
      );
    } finally {
      sub.close();
      container.dispose();
      await fixture.db.execute('PRAGMA query_only = OFF');
    }
  });
}
