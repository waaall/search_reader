// 内容解码回归：覆盖任意分块位置、严格错误传播及提前停止后的流释放。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/encoding/utf8_content_decoder.dart';

void main() {
  for (final text in [
    '',
    'A',
    '\u0000',
    '\uFEFF',
    '\uFEFF\uFEFF',
    '\uFEFF正文🙂',
    '甲\uFEFF尾',
    '\uFEFE�',
  ]) {
    test('普通与流式解码在所有分块位置保持一致：${jsonEncode(text)}', () async {
      final bytes = utf8.encode(text);
      expect(Utf8ContentDecoder.decode(bytes), text);
      for (var split = 0; split <= bytes.length; split++) {
        final chunks = Stream.fromIterable([
          bytes.sublist(0, split),
          <int>[],
          bytes.sublist(split),
        ]);
        expect(await Utf8ContentDecoder.decodeStream(chunks).join(), text);
      }
    });
  }

  test('提前结束解码会释放字节流，不预读整份正文', () async {
    var released = false;
    Stream<List<int>> chunks() async* {
      try {
        yield [0xEF];
        yield [0xBB];
        yield [0xBF];
        yield utf8.encode('正文');
        throw StateError('不应读取正文以外的块');
      } finally {
        released = true;
      }
    }

    expect(await Utf8ContentDecoder.decodeStream(chunks()).first, '\uFEFF');
    expect(released, isTrue);
  });

  test('正文流错误原样传播，不被 BOM 处理掩盖', () async {
    final error = StateError('模拟正文读取失败');
    Stream<List<int>> chunks() async* {
      yield [0xEF, 0xBB, 0xBF];
      throw error;
    }

    await expectLater(
      Utf8ContentDecoder.decodeStream(chunks()).join(),
      throwsA(same(error)),
    );
  });
}
