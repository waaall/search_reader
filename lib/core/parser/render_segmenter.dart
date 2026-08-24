// 渲染分片策略：按容量聚合零碎段落，并尽量把切点放在自然文本边界。
import 'dart:convert';

import 'book_format.dart';

class ReaderRenderPolicy {
  static const defaults = ReaderRenderPolicy();

  // 目标值控制常规分片大小，硬上限保证任何单个渲染单元都有明确边界。
  static const defaultTargetChars = 16 * 1024;
  static const defaultMaxChars = 24 * 1024;
  static const defaultMinNaturalBoundaryChars = 8 * 1024;
  static const defaultPaginationProbeChars = 2 * 1024;
  static const defaultPaginationMaxProbeChars = 32 * 1024;
  static const defaultTextCacheSegments = 5;
  static const defaultPageHistoryCount = 12;

  final int targetChars;
  final int maxChars;
  final int minNaturalBoundaryChars;
  final int paginationProbeChars;
  final int paginationMaxProbeChars;
  final int textCacheSegments;
  final int pageHistoryCount;

  const ReaderRenderPolicy({
    this.targetChars = defaultTargetChars,
    this.maxChars = defaultMaxChars,
    this.minNaturalBoundaryChars = defaultMinNaturalBoundaryChars,
    this.paginationProbeChars = defaultPaginationProbeChars,
    this.paginationMaxProbeChars = defaultPaginationMaxProbeChars,
    this.textCacheSegments = defaultTextCacheSegments,
    this.pageHistoryCount = defaultPageHistoryCount,
  }) : assert(targetChars > 0),
       assert(maxChars >= targetChars),
       assert(minNaturalBoundaryChars > 0),
       assert(minNaturalBoundaryChars <= targetChars),
       assert(paginationProbeChars > 0),
       assert(paginationMaxProbeChars >= paginationProbeChars),
       assert(textCacheSegments > 0),
       assert(pageHistoryCount > 0);
}

class RenderSegmentRange {
  final int start;
  final int end;

  const RenderSegmentRange(this.start, this.end);

  int get length => end - start;
}

class RenderSegmenter {
  final ReaderRenderPolicy policy;

  const RenderSegmenter({this.policy = ReaderRenderPolicy.defaults});

  // 返回范围完整覆盖 [start, end)，不会删除或插入任何正文字符。
  List<RenderSegmentRange> splitRange(String text, int start, int end) {
    if (start < 0 || end < start || end > text.length) {
      throw RangeError('渲染分片字符范围无效：[$start, $end)');
    }
    if (start == end) return [RenderSegmentRange(start, end)];

    final result = <RenderSegmentRange>[];
    var cursor = start;
    while (end - cursor > policy.maxChars) {
      final cut = chooseCutInRange(text, cursor, end);
      if (cut <= cursor || cut > end) {
        throw StateError('渲染分片没有向前推进');
      }
      result.add(RenderSegmentRange(cursor, cut));
      cursor = cut;
    }
    result.add(RenderSegmentRange(cursor, end));

    // 自然边界可能留下很短的尾片；未超过硬上限时并回前片。
    if (result.length >= 2 &&
        result.last.length < policy.minNaturalBoundaryChars) {
      final previous = result[result.length - 2];
      final tail = result.last;
      if (tail.end - previous.start <= policy.maxChars) {
        result
          ..removeLast()
          ..removeLast()
          ..add(RenderSegmentRange(previous.start, tail.end));
      }
    }
    return result;
  }

  // 输入至少比硬上限长；在目标值附近选择最近的换行，其次选择标点或空白。
  int chooseCut(String text) => chooseCutInRange(text, 0, text.length);

  int chooseCutInRange(String text, int start, int end) {
    if (start < 0 || end < start || end > text.length) {
      throw RangeError('渲染分片字符范围无效：[$start, $end)');
    }
    if (end - start <= policy.maxChars) return end;
    final min = (start + policy.minNaturalBoundaryChars).clamp(start + 1, end);
    final target = (start + policy.targetChars).clamp(min, end);
    final max = (start + policy.maxChars).clamp(target, end);

    final newline = _nearestBoundary(text, min, target, max, _isNewline);
    if (newline != null) return _safeEnd(text, newline);
    final punctuation = _nearestBoundary(
      text,
      min,
      target,
      max,
      _isSoftBoundary,
    );
    return _safeEnd(text, punctuation ?? max);
  }

  int? _nearestBoundary(
    String text,
    int min,
    int target,
    int max,
    bool Function(int codeUnit) accepts,
  ) {
    final radius = max - min;
    for (var distance = 0; distance <= radius; distance++) {
      final after = target + distance;
      if (after <= max && after > 0 && accepts(text.codeUnitAt(after - 1))) {
        return after;
      }
      final before = target - distance;
      if (before >= min && before > 0 && accepts(text.codeUnitAt(before - 1))) {
        return before;
      }
    }
    return null;
  }

  bool _isNewline(int codeUnit) => codeUnit == 0x0A;

  bool _isSoftBoundary(int codeUnit) => switch (codeUnit) {
    0x20 || // 半角空格
    0x09 || // 制表符
    0x3000 || // 全角空格
    0x3002 || // 。
    0xFF01 || // ！
    0xFF1F || // ？
    0xFF1B || // ；
    0x2026 || // …
    0x2E || // .
    0x21 || // !
    0x3F || // ?
    0x3B => true,
    _ => false,
  };

  int _safeEnd(String text, int end) {
    if (end > 0 &&
        end < text.length &&
        _isHighSurrogate(text.codeUnitAt(end - 1)) &&
        _isLowSurrogate(text.codeUnitAt(end))) {
      return end - 1;
    }
    return end;
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}

// 旧书补建使用流式输入，内存中只保留略大于一个分片的正文。
class StreamingRenderSegmentBuilder {
  final RenderSegmenter segmenter;

  const StreamingRenderSegmentBuilder({
    this.segmenter = const RenderSegmenter(),
  });

  Future<List<RenderSegmentDescriptor>> build({
    required Stream<String> chunks,
    required int startChar,
    required int endChar,
    required int startByte,
    required int endByte,
  }) async {
    final result = <RenderSegmentDescriptor>[];
    var buffer = '';
    var charCursor = startChar;
    var byteCursor = startByte;

    Future<void> flushPrefix(int cut) async {
      final content = buffer.substring(0, cut);
      final byteLength = utf8.encode(content).length;
      result.add(
        RenderSegmentDescriptor(
          startChar: charCursor,
          endChar: charCursor + content.length,
          startByte: byteCursor,
          endByte: byteCursor + byteLength,
        ),
      );
      charCursor += content.length;
      byteCursor += byteLength;
      buffer = buffer.substring(cut);
    }

    await for (final chunk in chunks) {
      buffer += chunk;
      while (buffer.length > segmenter.policy.maxChars) {
        await flushPrefix(segmenter.chooseCut(buffer));
      }
    }
    if (buffer.isNotEmpty || result.isEmpty) {
      await flushPrefix(buffer.length);
    }

    // 最后两片可安全合并时消除过小尾片，不需要重新读取正文。
    if (result.length >= 2 &&
        result.last.charCount < segmenter.policy.minNaturalBoundaryChars) {
      final previous = result[result.length - 2];
      final tail = result.last;
      if (tail.endChar - previous.startChar <= segmenter.policy.maxChars) {
        result
          ..removeLast()
          ..removeLast()
          ..add(
            RenderSegmentDescriptor(
              startChar: previous.startChar,
              endChar: tail.endChar,
              startByte: previous.startByte,
              endByte: tail.endByte,
            ),
          );
      }
    }

    if (charCursor != endChar || byteCursor != endByte) {
      throw StateError(
        '渲染分片范围与章节不一致：字符 $charCursor/$endChar，字节 $byteCursor/$endByte',
      );
    }
    return result;
  }
}
