// 分片阅读回归测试：验证懒分页跨片续排，以及滚动模式不会构建整章正文。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/parser/render_segmenter.dart';
import 'package:search_reader/domain/render_segment.dart';
import 'package:search_reader/features/reader/lazy_chapter_paginator.dart';
import 'package:search_reader/features/reader/reader_page.dart';
import 'package:search_reader/features/reader/segment_text_source.dart';
import 'package:search_reader/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('翻页窗口可以跨渲染分片且前后页范围连续', () async {
    const parts = ['第一片没有强制页尾。', '第二片继续同一页。', '第三片结束。'];
    final segments = _segmentsFor(parts);
    final source = SegmentTextSource(
      segments: segments,
      chapterStartChar: 0,
      readSegment: (index) async => parts[index],
      initialSegmentIndex: 0,
      initialSegmentText: parts.first,
      policy: const ReaderRenderPolicy(
        targetChars: 8,
        maxChars: 16,
        minNaturalBoundaryChars: 4,
        paginationProbeChars: 4,
        paginationMaxProbeChars: 64,
      ),
    );
    const paginator = TextStyle(fontSize: 16, height: 1.4);
    final engine = LazyChapterPaginator(
      source: source,
      style: paginator,
      contentWidth: 1000,
      contentHeight: 1000,
      policy: source.policy,
    );

    final page = await engine.pageFrom(0);
    expect(page.text, parts.join());
    expect(page.endOffset, parts.join().length);

    final narrow = LazyChapterPaginator(
      source: source,
      style: paginator,
      contentWidth: 90,
      contentHeight: 45,
      policy: source.policy,
    );
    final first = await narrow.pageFrom(0);
    final second = await narrow.pageFrom(first.endOffset);
    final previous = await narrow.pageEndingAt(second.startOffset);
    expect(first.endOffset, second.startOffset);
    expect(previous.startOffset, first.startOffset);
    expect(previous.endOffset, first.endOffset);
  });

  test('分片文本缓存有界，淘汰后才重新读取', () async {
    const parts = ['零', '一', '二'];
    final reads = <int>[];
    final source = SegmentTextSource(
      segments: _segmentsFor(parts),
      chapterStartChar: 0,
      readSegment: (index) async {
        reads.add(index);
        return parts[index];
      },
      initialSegmentIndex: 0,
      initialSegmentText: parts.first,
      policy: const ReaderRenderPolicy(
        targetChars: 2,
        maxChars: 4,
        minNaturalBoundaryChars: 1,
        textCacheSegments: 2,
      ),
    );

    await source.textAt(1);
    await source.textAt(2);
    await source.textAt(0);
    expect(reads, [1, 2, 0]);
  });

  testWidgets('滚动模式从中间分片启动时只构建附近正文', (tester) async {
    final parts = List.generate(80, (index) => '分片$index ${'正文' * 400}\n');
    final segments = _segmentsFor(parts);
    final reads = <int>[];
    var reportedOffset = segments[40].startChar;
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SegmentedScrollReaderView(
            segments: segments,
            chapterStartChar: 0,
            initialSegmentIndex: 40,
            initialSegmentText: parts[40],
            loadSegment: (index) async {
              reads.add(index);
              return parts[index];
            },
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
            textStyle: const TextStyle(fontSize: 18, height: 1.7),
            themeBg: Colors.white,
            themeFg: Colors.black,
            chapterTitle: '正文',
            menuVisible: false,
            initialCharOffset: segments[40].startChar,
            onCharOffsetChanged: (offset) => reportedOffset = offset,
            onTapCenter: () {},
            onPrevChapter: null,
            onNextChapter: null,
            onOpenChapters: () {},
            onOpenSettings: () {},
            onAddBookmark: (_) {},
            onBack: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('分片40'), findsOneWidget);
    expect(find.textContaining('分片0'), findsNothing);
    expect(find.textContaining('分片79'), findsNothing);
    expect(reads.length, lessThan(10));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollController.offset, greaterThan(0));
    final forwardOffset = reportedOffset;
    expect(forwardOffset, greaterThan(segments[40].startChar));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 420));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reportedOffset, lessThan(forwardOffset));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reportedOffset, lessThan(segments[40].startChar));
  });
}

List<RenderSegment> _segmentsFor(List<String> parts) {
  final result = <RenderSegment>[];
  var cursor = 0;
  for (var index = 0; index < parts.length; index++) {
    final start = cursor;
    cursor += parts[index].length;
    result.add(
      RenderSegment(
        id: index + 1,
        chapterId: 1,
        segmentIndex: index,
        startChar: start,
        endChar: cursor,
        startByte: start,
        endByte: cursor,
      ),
    );
  }
  return result;
}
