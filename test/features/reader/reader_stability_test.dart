// 阅读稳定性回归：覆盖系统缩放变化、分页连续性和非均匀段落的字符定位。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/domain/render_segment.dart';
import 'package:search_reader/features/reader/lazy_chapter_paginator.dart';
import 'package:search_reader/features/reader/reader_page.dart';
import 'package:search_reader/features/reader/reader_text_layout.dart';
import 'package:search_reader/features/reader/segment_text_source.dart';
import 'package:search_reader/l10n/app_localizations.dart';

const _style = TextStyle(fontSize: 18, height: 1.7);
const _padding = EdgeInsets.fromLTRB(20, 48, 20, 32);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scale in [1.0, 1.5, 2.0, 3.0]) {
    test('缩放 $scale 倍时每页实际高度受限且拼回正文无缺失', () async {
      final text = '这是带有标点和换行的正文。🙂\n' * 40;
      final layout = ReaderTextLayout(textScaler: TextScaler.linear(scale));
      final source = SegmentTextSource(
        segments: [_segment(text)],
        chapterStartChar: 0,
        readSegment: (_) async => text,
        initialSegmentIndex: 0,
        initialSegmentText: text,
      );
      final paginator = LazyChapterPaginator(
        source: source,
        style: _style,
        contentWidth: 360,
        contentHeight: 500,
        layout: layout,
      );
      var cursor = 0;
      final pages = <String>[];
      while (cursor < text.length) {
        final page = await paginator.pageFrom(cursor);
        expect(page.endOffset, greaterThan(cursor));
        final painter = layout.createPainter(page.text, _style, 360);
        expect(painter.height, lessThanOrEqualTo(500));
        painter.dispose();
        pages.add(page.text);
        final backwards = await paginator.pageEndingAt(page.endOffset);
        final backwardsPainter = layout.createPainter(
          backwards.text,
          _style,
          360,
        );
        expect(backwardsPainter.height, lessThanOrEqualTo(500));
        backwardsPainter.dispose();
        expect(
          backwards.text,
          text.substring(backwards.startOffset, page.endOffset),
        );
        cursor = page.endOffset;
      }
      expect(pages.join(), text);
    });
  }

  testWidgets('动态系统缩放保留当前页起点并重新分页，前后页仍连续', (tester) async {
    final text = '天地玄黄宇宙洪荒日月盈昃辰宿列张' * 400;
    var reportedOffset = 0;
    Widget subject(double scale) => _app(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: SegmentedPaginatedReaderView(
          segments: [_segment(text)],
          chapterStartChar: 0,
          initialSegmentIndex: 0,
          initialSegmentText: text,
          initialCharOffset: 0,
          loadSegment: (_) async => text,
          contentWidth: 760,
          contentHeight: 520,
          padding: _padding,
          textStyle: _style,
          themeBg: Colors.white,
          themeFg: Colors.black,
          chapterTitle: '正文',
          menuVisible: false,
          chapterBookmarkOffsets: const {},
          onCharOffsetChanged: (offset) => reportedOffset = offset,
          onTapCenter: () {},
          onPrevChapter: null,
          onNextChapter: null,
          onOpenChapters: () {},
          onOpenSettings: () {},
          onAddBookmark: (_) {},
          onBack: (_) async {},
          searchQuery: '天地',
          activeSearchOffset: 0,
          activeSearchLength: 2,
        ),
      ),
    );

    await tester.pumpWidget(subject(1));
    await tester.pumpAndSettle();
    final firstLength = _bodyParagraph(tester, text).text.toPlainText().length;
    await tester.tapAt(const Offset(750, 300));
    await tester.pumpAndSettle();
    expect(reportedOffset, firstLength);

    await tester.pumpWidget(subject(2));
    await tester.pumpAndSettle();
    final paragraph = _bodyParagraph(tester, text);
    final pageText = paragraph.text.toPlainText();
    expect(reportedOffset, firstLength);
    expect(
      pageText,
      text.substring(firstLength, firstLength + pageText.length),
    );
    expect(pageText.length, lessThan(firstLength));
    final lastBox = paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: pageText.length - 1,
            extentOffset: pageText.length,
          ),
        )
        .last;
    expect(lastBox.bottom, lessThanOrEqualTo(520));

    await tester.tapAt(const Offset(750, 300));
    await tester.pumpAndSettle();
    expect(reportedOffset, firstLength + pageText.length);
    await tester.tapAt(const Offset(30, 300));
    await tester.pumpAndSettle();
    expect(reportedOffset, firstLength);
  });

  testWidgets('短段落密集时搜索目标可见，保存进度对应实际可见行', (tester) async {
    final prefix = '甲\n' * 200;
    final text = '$prefix目标位置${'后文' * 6000}';
    final offset = prefix.length;
    var reportedOffset = offset;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SegmentedScrollReaderView(
          segments: [_segment(text)],
          chapterStartChar: 0,
          initialSegmentIndex: 0,
          initialSegmentText: text,
          initialCharOffset: offset,
          loadSegment: (_) async => text,
          controller: controller,
          padding: _padding,
          textStyle: _style,
          themeBg: Colors.white,
          themeFg: Colors.black,
          chapterTitle: '正文',
          menuVisible: false,
          onCharOffsetChanged: (value) => reportedOffset = value,
          onTapCenter: () {},
          onPrevChapter: null,
          onNextChapter: null,
          onOpenChapters: () {},
          onOpenSettings: () {},
          onAddBookmark: (_) {},
          onBack: (_) async {},
          searchQuery: '目标位置',
          activeSearchOffset: offset,
          activeSearchLength: 4,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = _bodyParagraph(tester, text);
    final targetBox = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 4),
        )
        .first;
    final targetY = paragraph
        .localToGlobal(Offset(targetBox.left, targetBox.top))
        .dy;
    expect(targetY, inInclusiveRange(0, 600));
    expect(reportedOffset, offset);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    final visible = paragraph
        .getPositionForOffset(paragraph.globalToLocal(const Offset(20, 0)))
        .offset;
    expect(reportedOffset, visible);
    expect(reportedOffset, greaterThan(offset));
  });
}

Widget _app(Widget reader) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: reader),
);

RenderParagraph _bodyParagraph(WidgetTester tester, String source) {
  final finder = find.byWidgetPredicate((widget) {
    if (widget is! RichText) return false;
    final text = widget.text.toPlainText();
    return text.length > 16 && source.contains(text);
  });
  expect(finder, findsOneWidget);
  return tester.renderObject<RenderParagraph>(finder);
}

RenderSegment _segment(String text) => RenderSegment(
  id: 1,
  chapterId: 1,
  segmentIndex: 0,
  startChar: 0,
  endChar: text.length,
  startByte: 0,
  endByte: utf8.encode(text).length,
);
