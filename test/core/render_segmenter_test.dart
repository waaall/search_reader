// 渲染分片回归测试：覆盖零碎段落聚合、超长单段和流式字节坐标。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/parser/render_segmenter.dart';

void main() {
  const policy = ReaderRenderPolicy(
    targetChars: 20,
    maxChars: 30,
    minNaturalBoundaryChars: 10,
  );
  const segmenter = RenderSegmenter(policy: policy);

  test('大量零碎段落会聚合到容量附近而不是一段一片', () {
    final text = List.generate(40, (index) => '第$index行').join('\n');
    final ranges = segmenter.splitRange(text, 0, text.length);

    expect(ranges.length, lessThan(20));
    expect(ranges.every((range) => range.length <= policy.maxChars), isTrue);
    expect(
      ranges.map((range) => text.substring(range.start, range.end)).join(),
      text,
    );
    expect(
      ranges
          .take(ranges.length - 1)
          .every(
            (range) => text.substring(range.start, range.end).endsWith('\n'),
          ),
      isTrue,
    );
  });

  test('没有换行的超长单段仍受硬上限约束且不切断代理对', () {
    final text = '${'字' * 19}🙂${'文' * 80}';
    final ranges = segmenter.splitRange(text, 0, text.length);

    expect(ranges.length, greaterThan(1));
    expect(ranges.every((range) => range.length <= policy.maxChars), isTrue);
    expect(
      ranges.map((range) => text.substring(range.start, range.end)).join(),
      text,
    );
    for (final range in ranges.take(ranges.length - 1)) {
      expect(_cutsSurrogatePair(text, range.end), isFalse);
    }
  });

  test('流式补建保留非零起点下的字符和 UTF-8 字节连续性', () async {
    final chapter = '短段一\n短段二🙂\n${'长' * 60}';
    final chapterBytes = utf8.encode(chapter).length;
    final descriptors =
        await const StreamingRenderSegmentBuilder(segmenter: segmenter).build(
          chunks: Stream.fromIterable([
            chapter.substring(0, 7),
            chapter.substring(7, 15),
            chapter.substring(15),
          ]),
          startChar: 100,
          endChar: 100 + chapter.length,
          startByte: 300,
          endByte: 300 + chapterBytes,
        );

    expect(descriptors.first.startChar, 100);
    expect(descriptors.first.startByte, 300);
    expect(descriptors.last.endChar, 100 + chapter.length);
    expect(descriptors.last.endByte, 300 + chapterBytes);
    for (var index = 1; index < descriptors.length; index++) {
      expect(descriptors[index].startChar, descriptors[index - 1].endChar);
      expect(descriptors[index].startByte, descriptors[index - 1].endByte);
    }
  });
}

bool _cutsSurrogatePair(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return false;
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  return before >= 0xD800 &&
      before <= 0xDBFF &&
      after >= 0xDC00 &&
      after <= 0xDFFF;
}
