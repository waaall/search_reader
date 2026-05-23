import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/features/reader/pagination.dart';

// TextPaginator 走 TextPainter 度量，依赖 Flutter 绑定（含默认字体）
// 用法等价于 testWidgets 默认环境；显式 ensureInitialized 让脱离 widget 上下文也能跑
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 16, height: 1.6);

  group('TextPaginator.paginate', () {
    test('空文本返回单空页', () {
      final p = TextPaginator.paginate(
        text: '',
        style: style,
        contentWidth: 300,
        contentHeight: 600,
      );
      expect(p.pageCount, 1);
      expect(p.pages.first, '');
    });

    test('零宽度返回单空页', () {
      final p = TextPaginator.paginate(
        text: '一些内容',
        style: style,
        contentWidth: 0,
        contentHeight: 600,
      );
      expect(p.pageCount, 1);
    });

    test('零高度返回单空页', () {
      final p = TextPaginator.paginate(
        text: '一些内容',
        style: style,
        contentWidth: 300,
        contentHeight: 0,
      );
      expect(p.pageCount, 1);
    });

    test('小文本 + 大画布 → 单页装下全部内容', () {
      const text = '第一段内容\n第二段内容\n第三段内容';
      final p = TextPaginator.paginate(
        text: text,
        style: style,
        contentWidth: 600,
        contentHeight: 6000,
      );
      expect(p.pageCount, 1);
      // 三段都应保留在唯一一页内
      expect(p.pages.first.contains('第一段'), true);
      expect(p.pages.first.contains('第二段'), true);
      expect(p.pages.first.contains('第三段'), true);
    });

    test('长文本 + 小画布 → 多页且每段都能被找到', () {
      // 构造 200 段，足以撑出多页
      final text = List.generate(200, (i) => '第$i段示意文字占位内容').join('\n');
      final p = TextPaginator.paginate(
        text: text,
        style: const TextStyle(fontSize: 20, height: 1.8),
        contentWidth: 200,
        contentHeight: 300,
      );
      expect(p.pageCount, greaterThan(1));

      // 拼回所有页内容，每段都应出现在某一页中
      final joined = p.pages.join();
      expect(joined.contains('第0段'), true);
      expect(joined.contains('第100段'), true);
      expect(joined.contains('第199段'), true);
    });

    test('超长单段 → 段内二分切，至少两页', () {
      // 单段没有 \n，长度足以超过一页可容纳
      final longParagraph = '一' * 5000;
      final p = TextPaginator.paginate(
        text: longParagraph,
        style: const TextStyle(fontSize: 22, height: 1.6),
        contentWidth: 200,
        contentHeight: 200,
      );
      expect(p.pageCount, greaterThan(1));
      // 切片拼回应等于原段（含末尾追加的 \n）
      final joined = p.pages.join();
      expect(joined.contains('一一一一一'), true);
    });
  });

  group('Pagination 位置映射', () {
    test('pageOfOffset(0) 在第一页', () {
      const text = 'aaa\nbbb\nccc\nddd\neee';
      final p = TextPaginator.paginate(
        text: text,
        style: style,
        contentWidth: 300,
        contentHeight: 600,
      );
      expect(p.pageOfOffset(0), 0);
    });

    test('offsetOfPage(0) 是 0', () {
      const text = '段一\n段二\n段三';
      final p = TextPaginator.paginate(
        text: text,
        style: style,
        contentWidth: 300,
        contentHeight: 600,
      );
      expect(p.offsetOfPage(0), 0);
    });

    test('末尾偏移落在有效页范围内', () {
      const text = 'aaa\nbbb\nccc\nddd\neee';
      final p = TextPaginator.paginate(
        text: text,
        style: style,
        contentWidth: 300,
        contentHeight: 600,
      );
      final lastPage = p.pageOfOffset(text.length - 1);
      expect(lastPage, lessThan(p.pageCount));
      expect(lastPage, greaterThanOrEqualTo(0));
    });

    test('offsetOfPage 单调递增', () {
      // 长文本确保至少几页
      final text = List.generate(100, (i) => '段$i 内容').join('\n');
      final p = TextPaginator.paginate(
        text: text,
        style: const TextStyle(fontSize: 20),
        contentWidth: 200,
        contentHeight: 300,
      );
      var last = -1;
      for (var i = 0; i < p.pageCount; i++) {
        final off = p.offsetOfPage(i);
        expect(off, greaterThanOrEqualTo(last));
        last = off;
      }
    });

    test('pageOfOffset 与 offsetOfPage 往返一致', () {
      final text = List.generate(50, (i) => '行$i').join('\n');
      final p = TextPaginator.paginate(
        text: text,
        style: const TextStyle(fontSize: 20),
        contentWidth: 200,
        contentHeight: 300,
      );
      // 任取一页起点偏移，pageOfOffset 应该返回该页（或紧邻页，因边界条件）
      for (var i = 0; i < p.pageCount; i++) {
        final off = p.offsetOfPage(i);
        // pageOfOffset 的实现是 charOffset < 累计长度 → 该页
        // 取 off 时，累计长度恰好 = off + 当前页长度，所以 off 命中当前页
        final pageOf = p.pageOfOffset(off);
        expect(pageOf, i);
      }
    });
  });
}
