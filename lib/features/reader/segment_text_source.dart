// 章节分片文本源：提供有限大小的前向/后向窗口，并用 LRU 限制正文缓存。
import 'dart:collection';

import '../../core/parser/render_segmenter.dart';
import '../../domain/render_segment.dart';

typedef SegmentTextReader = Future<String> Function(int segmentIndex);

int findSegmentIndexForChapterOffset(
  List<RenderSegment> segments,
  int chapterStartChar,
  int chapterOffset, {
  bool previous = false,
}) {
  if (segments.isEmpty) return 0;
  final chapterCharCount = segments.last.endChar - chapterStartChar;
  final clamped = chapterOffset.clamp(0, chapterCharCount);
  final target = previous && clamped > 0 ? clamped - 1 : clamped;
  final global = chapterStartChar + target;
  for (var index = 0; index < segments.length; index++) {
    if (global < segments[index].endChar || index == segments.length - 1) {
      return index;
    }
  }
  return segments.length - 1;
}

class SegmentTextWindow {
  final int startOffset;
  final String text;
  final bool reachesChapterStart;
  final bool reachesChapterEnd;

  const SegmentTextWindow({
    required this.startOffset,
    required this.text,
    required this.reachesChapterStart,
    required this.reachesChapterEnd,
  });

  int get endOffset => startOffset + text.length;
}

class SegmentTextSource {
  SegmentTextSource({
    required this.segments,
    required this.chapterStartChar,
    required this.readSegment,
    required int initialSegmentIndex,
    String? initialSegmentText,
    this.policy = ReaderRenderPolicy.defaults,
  }) {
    if (initialSegmentText != null) {
      _cache[initialSegmentIndex] = Future.value(initialSegmentText);
    }
  }

  final List<RenderSegment> segments;
  final int chapterStartChar;
  final SegmentTextReader readSegment;
  final ReaderRenderPolicy policy;
  final LinkedHashMap<int, Future<String>> _cache = LinkedHashMap();

  int get chapterCharCount =>
      segments.isEmpty ? 0 : segments.last.endChar - chapterStartChar;

  Future<String> textAt(int index) {
    if (index < 0 || index >= segments.length) {
      return Future.error(RangeError.index(index, segments, 'index'));
    }
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return cached;
    }
    final pending = readSegment(index);
    _cache[index] = pending;
    pending.catchError((Object _) {
      if (identical(_cache[index], pending)) _cache.remove(index);
      return '';
    });
    while (_cache.length > policy.textCacheSegments) {
      _cache.remove(_cache.keys.first);
    }
    return pending;
  }

  void prefetchAround(int index) {
    if (index > 0) textAt(index - 1).ignore();
    if (index + 1 < segments.length) textAt(index + 1).ignore();
  }

  int segmentIndexForOffset(int chapterOffset, {bool previous = false}) {
    return findSegmentIndexForChapterOffset(
      segments,
      chapterStartChar,
      chapterOffset,
      previous: previous,
    );
  }

  int segmentStartOffset(int index) =>
      segments[index].startChar - chapterStartChar;

  Future<SegmentTextWindow> readForward(int startOffset, int maxChars) async {
    final start = startOffset.clamp(0, chapterCharCount);
    if (segments.isEmpty || start >= chapterCharCount || maxChars <= 0) {
      return SegmentTextWindow(
        startOffset: start,
        text: '',
        reachesChapterStart: start == 0,
        reachesChapterEnd: start >= chapterCharCount,
      );
    }

    final buffer = StringBuffer();
    var index = segmentIndexForOffset(start);
    var cursor = start;
    while (index < segments.length && buffer.length < maxChars) {
      final segment = segments[index];
      final text = await textAt(index);
      final segmentStart = segment.startChar - chapterStartChar;
      final localStart = (cursor - segmentStart).clamp(0, text.length);
      final available = text.length - localStart;
      var take = (maxChars - buffer.length).clamp(0, available);
      if (localStart + take < text.length &&
          take > 0 &&
          _isHighSurrogate(text.codeUnitAt(localStart + take - 1)) &&
          _isLowSurrogate(text.codeUnitAt(localStart + take))) {
        // 极小探测窗口也必须至少包含一个完整 Unicode 代理对。
        take = take == 1 ? 2 : take - 1;
      }
      if (take > 0) {
        buffer.write(text.substring(localStart, localStart + take));
        cursor += take;
      }
      // 避开代理对后窗口可能尚未填满，不能跳过当前片中还没有读取的正文。
      if (take >= available) index++;
    }
    return SegmentTextWindow(
      startOffset: start,
      text: buffer.toString(),
      reachesChapterStart: start == 0,
      reachesChapterEnd: cursor >= chapterCharCount,
    );
  }

  Future<SegmentTextWindow> readBackward(int endOffset, int maxChars) async {
    final end = endOffset.clamp(0, chapterCharCount);
    if (segments.isEmpty || end <= 0 || maxChars <= 0) {
      return SegmentTextWindow(
        startOffset: end,
        text: '',
        reachesChapterStart: end <= 0,
        reachesChapterEnd: end == chapterCharCount,
      );
    }

    final parts = <String>[];
    var index = segmentIndexForOffset(end, previous: true);
    var cursor = end;
    var collected = 0;
    while (index >= 0 && collected < maxChars) {
      final segment = segments[index];
      final text = await textAt(index);
      final segmentStart = segment.startChar - chapterStartChar;
      final localEnd = (cursor - segmentStart).clamp(0, text.length);
      var take = (maxChars - collected).clamp(0, localEnd);
      final localStart = localEnd - take;
      if (localStart > 0 &&
          localStart < text.length &&
          _isLowSurrogate(text.codeUnitAt(localStart)) &&
          _isHighSurrogate(text.codeUnitAt(localStart - 1))) {
        take++;
      }
      if (take > 0) {
        parts.add(text.substring(localEnd - take, localEnd));
        cursor -= take;
        collected += take;
      }
      index--;
    }
    return SegmentTextWindow(
      startOffset: cursor,
      text: parts.reversed.join(),
      reachesChapterStart: cursor <= 0,
      reachesChapterEnd: end == chapterCharCount,
    );
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}
