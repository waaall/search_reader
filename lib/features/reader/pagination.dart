import 'package:flutter/painting.dart';

// 分页结果：每个元素是一页的文本
class Pagination {
  final List<String> pages;
  const Pagination(this.pages);

  int get pageCount => pages.length;

  // 根据章节内字符偏移定位到对应页
  int pageOfOffset(int charOffset) {
    var consumed = 0;
    for (var i = 0; i < pages.length; i++) {
      consumed += pages[i].length;
      if (charOffset < consumed) return i;
    }
    return pages.length - 1;
  }

  // 反向：第 N 页起始字符在章节内的偏移
  int offsetOfPage(int pageIndex) {
    var consumed = 0;
    for (var i = 0; i < pageIndex && i < pages.length; i++) {
      consumed += pages[i].length;
    }
    return consumed;
  }
}

// 文本分页：按段落累加高度，超出页高时切页
// 单段过长时用二分法在段内切分
class TextPaginator {
  // [text] 章节正文
  // [style] 文本样式（字号、行高、字体等）
  // [contentWidth] 文本可显示宽度（已减去内边距）
  // [contentHeight] 文本可显示高度（已减去内边距）
  static Pagination paginate({
    required String text,
    required TextStyle style,
    required double contentWidth,
    required double contentHeight,
  }) {
    if (text.isEmpty || contentWidth <= 0 || contentHeight <= 0) {
      return const Pagination(['']);
    }

    // 拆段：保留空段（用作段间间距）
    final paragraphs = text.split('\n');
    final pages = <String>[];
    final pageBuffer = StringBuffer();
    var pageHeight = 0.0;

    void flushPage() {
      if (pageBuffer.isNotEmpty) {
        pages.add(pageBuffer.toString());
        pageBuffer.clear();
        pageHeight = 0;
      }
    }

    for (final raw in paragraphs) {
      // 段尾保留 \n，用于在 TextPainter 中产生段距
      final segment = '$raw\n';
      final h = _measureHeight(segment, style, contentWidth);

      if (pageHeight + h <= contentHeight) {
        pageBuffer.write(segment);
        pageHeight += h;
        continue;
      }

      // 装不下：先把当前页落盘
      flushPage();

      if (h <= contentHeight) {
        pageBuffer.write(segment);
        pageHeight = h;
      } else {
        // 单段超过一页：段内二分切
        var remaining = segment;
        while (remaining.isNotEmpty) {
          final cut = _findFitPrefix(
            text: remaining,
            style: style,
            contentWidth: contentWidth,
            contentHeight: contentHeight,
          );
          pages.add(remaining.substring(0, cut));
          remaining = remaining.substring(cut);
        }
        pageHeight = 0;
      }
    }

    flushPage();
    if (pages.isEmpty) pages.add('');
    return Pagination(pages);
  }

  // 懒分页只测量当前位置之后的有限窗口，返回当前页可容纳的前缀长度。
  static int fitPrefixLength({
    required String text,
    required TextStyle style,
    required double contentWidth,
    required double contentHeight,
  }) {
    if (text.isEmpty) return 0;
    if (contentWidth <= 0 || contentHeight <= 0) return 1;
    if (_measureHeight(text, style, contentWidth) <= contentHeight) {
      return text.length;
    }
    return _findFitPrefix(
      text: text,
      style: style,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
  }

  // 向前翻页时返回能容纳的最长后缀起点，保证 [result, text.length) 完整成页。
  static int fitSuffixStart({
    required String text,
    required TextStyle style,
    required double contentWidth,
    required double contentHeight,
  }) {
    if (text.isEmpty) return 0;
    if (contentWidth <= 0 || contentHeight <= 0) {
      return _safeSuffixStart(text, text.length - 1);
    }
    if (_measureHeight(text, style, contentWidth) <= contentHeight) return 0;

    var lo = 0;
    var hi = text.length - 1;
    var best = text.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final start = _safeSuffixStart(text, mid);
      final h = _measureHeight(text.substring(start), style, contentWidth);
      if (h <= contentHeight) {
        best = start;
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    return best;
  }

  // 测量给定文本在指定宽度下的高度
  static double _measureHeight(String text, TextStyle style, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return tp.height;
  }

  // 二分找出能放入 contentHeight 的最长前缀字符数
  static int _findFitPrefix({
    required String text,
    required TextStyle style,
    required double contentWidth,
    required double contentHeight,
  }) {
    var lo = 1;
    var hi = text.length;
    var best = _safePrefixEnd(text, 1);
    while (lo <= hi) {
      final rawMid = (lo + hi) >> 1;
      final mid = _safePrefixEnd(text, rawMid);
      final h = _measureHeight(text.substring(0, mid), style, contentWidth);
      if (h <= contentHeight) {
        best = mid;
        lo = rawMid + 1;
      } else {
        hi = rawMid - 1;
      }
    }
    return best;
  }

  static int _safePrefixEnd(String text, int end) {
    if (end > 0 &&
        end < text.length &&
        _isHighSurrogate(text.codeUnitAt(end - 1)) &&
        _isLowSurrogate(text.codeUnitAt(end))) {
      return end + 1;
    }
    return end;
  }

  static int _safeSuffixStart(String text, int start) {
    if (start > 0 &&
        start < text.length &&
        _isLowSurrogate(text.codeUnitAt(start)) &&
        _isHighSurrogate(text.codeUnitAt(start - 1))) {
      return start - 1;
    }
    return start;
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}
