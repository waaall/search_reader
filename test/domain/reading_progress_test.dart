// 整本书进度摘要测试：验证真实字符位置换算与边界保护。

import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/domain/reading_progress.dart';

void main() {
  group('BookProgressSummary', () {
    test('按当前字符位置计算全书百分比', () {
      const summary = BookProgressSummary(
        bookId: 1,
        currentChar: 250,
        totalChars: 1000,
      );

      expect(summary.fraction, 0.25);
    });

    test('进度始终限制在 0 到 1 之间', () {
      const beforeStart = BookProgressSummary(
        bookId: 1,
        currentChar: -10,
        totalChars: 1000,
      );
      const afterEnd = BookProgressSummary(
        bookId: 2,
        currentChar: 1200,
        totalChars: 1000,
      );

      expect(beforeStart.fraction, 0);
      expect(afterEnd.fraction, 1);
    });

    test('空文本返回零进度', () {
      const summary = BookProgressSummary(
        bookId: 1,
        currentChar: 10,
        totalChars: 0,
      );

      expect(summary.fraction, 0);
    });
  });
}
