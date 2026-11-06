// 按需分页器：每次只测量一页附近的有限窗口，且允许页面跨越渲染分片。
import 'package:flutter/painting.dart';

import '../../core/parser/render_segmenter.dart';
import 'pagination.dart';
import 'reader_text_layout.dart';
import 'segment_text_source.dart';

class ReaderPageSlice {
  final int startOffset;
  final int endOffset;
  final String text;

  const ReaderPageSlice({
    required this.startOffset,
    required this.endOffset,
    required this.text,
  });
}

class LazyChapterPaginator {
  const LazyChapterPaginator({
    required this.source,
    required this.style,
    required this.contentWidth,
    required this.contentHeight,
    this.policy = ReaderRenderPolicy.defaults,
    this.layout = const ReaderTextLayout(),
  });

  final SegmentTextSource source;
  final TextStyle style;
  final double contentWidth;
  final double contentHeight;
  final ReaderRenderPolicy policy;
  final ReaderTextLayout layout;

  Future<ReaderPageSlice> pageFrom(int startOffset) async {
    final start = startOffset.clamp(0, source.chapterCharCount);
    if (start >= source.chapterCharCount) {
      return ReaderPageSlice(startOffset: start, endOffset: start, text: '');
    }

    var probeChars = policy.paginationProbeChars;
    while (true) {
      final window = await source.readForward(start, probeChars);
      if (window.text.isEmpty) {
        throw StateError('章节分片未能从偏移 $start 读取到正文');
      }
      final fit = TextPaginator.fitPrefixLength(
        text: window.text,
        style: style,
        contentWidth: contentWidth,
        contentHeight: contentHeight,
        layout: layout,
      );
      if (fit < window.text.length ||
          window.reachesChapterEnd ||
          probeChars >= policy.paginationMaxProbeChars) {
        final safeFit = fit.clamp(1, window.text.length);
        return ReaderPageSlice(
          startOffset: start,
          endOffset: start + safeFit,
          text: window.text.substring(0, safeFit),
        );
      }
      probeChars = (probeChars * 2).clamp(
        probeChars + 1,
        policy.paginationMaxProbeChars,
      );
    }
  }

  Future<ReaderPageSlice> pageEndingAt(int endOffset) async {
    final end = endOffset.clamp(0, source.chapterCharCount);
    if (end <= 0) {
      return ReaderPageSlice(startOffset: 0, endOffset: 0, text: '');
    }

    var probeChars = policy.paginationProbeChars;
    while (true) {
      final window = await source.readBackward(end, probeChars);
      final suffixStart = TextPaginator.fitSuffixStart(
        text: window.text,
        style: style,
        contentWidth: contentWidth,
        contentHeight: contentHeight,
        layout: layout,
      );
      if (suffixStart > 0 ||
          window.reachesChapterStart ||
          probeChars >= policy.paginationMaxProbeChars) {
        final start = window.startOffset + suffixStart;
        return ReaderPageSlice(
          startOffset: start,
          endOffset: end,
          text: window.text.substring(suffixStart),
        );
      }
      probeChars = (probeChars * 2).clamp(
        probeChars + 1,
        policy.paginationMaxProbeChars,
      );
    }
  }
}
