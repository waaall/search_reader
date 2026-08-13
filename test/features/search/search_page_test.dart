// 搜索页并发测试：确保旧请求不会覆盖最新输入对应的界面状态。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/db/daos.dart';
import 'package:search_reader/features/search/search_page.dart';
import 'package:search_reader/features/search/search_service.dart';
import 'package:search_reader/l10n/app_localizations.dart';

void main() {
  Widget buildSubject(SearchRunner search) {
    return ProviderScope(
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SearchPage(search: search, debounceDuration: Duration.zero),
      ),
    );
  }

  SearchHit hit(String label) => SearchHit(
    bookId: label.hashCode,
    bookTitle: '$label-book',
    chapterId: label.hashCode,
    chapterIndex: 0,
    chapterTitle: '$label-chapter',
    snippet: label,
    charOffset: 0,
  );

  testWidgets('较晚完成的旧查询不覆盖新查询结果', (tester) async {
    final completers = <String, Completer<List<SearchHit>>>{};
    final cancellationChecks = <String, SearchCancellationCheck?>{};

    Future<List<SearchHit>> search(
      String raw, {
      SearchCancellationCheck? isCancelled,
    }) {
      cancellationChecks[raw] = isCancelled;
      return (completers[raw] = Completer<List<SearchHit>>()).future;
    }

    await tester.pumpWidget(buildSubject(search));
    await tester.enterText(find.byType(TextField), 'old-query');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new-query');
    await tester.pump();

    expect(cancellationChecks['old-query']?.call(), isTrue);

    completers['new-query']!.complete([hit('new-result')]);
    await tester.pumpAndSettle();
    expect(find.text('new-result-book · new-result-chapter'), findsOneWidget);

    completers['old-query']!.complete([hit('old-result')]);
    await tester.pumpAndSettle();
    expect(find.text('new-result-book · new-result-chapter'), findsOneWidget);
    expect(find.text('old-result-book · old-result-chapter'), findsNothing);
  });

  testWidgets('清空输入后忽略未完成的旧查询', (tester) async {
    final completer = Completer<List<SearchHit>>();

    Future<List<SearchHit>> search(
      String raw, {
      SearchCancellationCheck? isCancelled,
    }) => completer.future;

    await tester.pumpWidget(buildSubject(search));
    await tester.enterText(find.byType(TextField), 'pending-query');
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);

    completer.complete([hit('stale-result')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
    expect(find.text('stale-result-book · stale-result-chapter'), findsNothing);
  });
}
