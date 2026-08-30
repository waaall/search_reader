import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/domain/chapter.dart';
import 'package:search_reader/features/reader/widgets/reader_drawer.dart';
import 'package:search_reader/l10n/app_localizations.dart';

void main() {
  Widget subject({
    required List<Chapter> chapters,
    required int currentIndex,
    void Function(int)? onJump,
  }) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChapterDirectory(
          chapters: chapters,
          currentIndex: currentIndex,
          onJump: onJump ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('长目录初次打开时定位到当前章节附近', (tester) async {
    final chapters = List.generate(500, _chapter);
    await tester.pumpWidget(subject(chapters: chapters, currentIndex: 320));
    await tester.pumpAndSettle();

    expect(find.text('当前第 321 / 500 章'), findsOneWidget);
    expect(find.byKey(const ValueKey('chapter-row-320')), findsOneWidget);
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('chapter-directory-list')),
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable.first);
    expect(state.position.pixels, greaterThan(0));
  });

  testWidgets('章节名搜索保留真实章节索引并可跳转', (tester) async {
    final chapters = List.generate(80, _chapter);
    var jumped = -1;
    await tester.pumpWidget(
      subject(
        chapters: chapters,
        currentIndex: 0,
        onJump: (index) => jumped = index,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('chapter-search-field')),
      '第57章',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chapter-row-57')), findsOneWidget);
    expect(find.text('1 条'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chapter-row-57')));
    expect(jumped, 57);
  });

  testWidgets('识别卷标题并折叠非当前卷', (tester) async {
    final chapters = [
      _chapter(0, title: '卷一 风起'),
      _chapter(1, title: '第一章 初见'),
      _chapter(2, title: '第二章 同行'),
      _chapter(3, title: '第二卷 山河'),
      _chapter(4, title: '第三章 重逢'),
    ];
    await tester.pumpWidget(subject(chapters: chapters, currentIndex: 4));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('volume-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('chapter-row-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('volume-row-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chapter-row-1')), findsOneWidget);
  });
}

Chapter _chapter(int index, {String? title}) {
  return Chapter(
    id: index + 1,
    bookId: 1,
    chapterIndex: index,
    title: title ?? '第$index章',
    startChar: index * 100,
    endChar: (index + 1) * 100,
    startByte: index * 100,
    endByte: (index + 1) * 100,
  );
}
