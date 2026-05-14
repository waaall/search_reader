import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/encoding/text_decoder.dart';

void main() {
  group('TextDecoder', () {
    test('UTF-8 无 BOM', () {
      final bytes = Uint8List.fromList(utf8.encode('你好世界'));
      final result = TextDecoder.decode(bytes);
      expect(result.content, '你好世界');
      expect(result.encoding, DetectedEncoding.utf8);
    });

    test('UTF-8 带 BOM', () {
      final bytes = Uint8List.fromList(
          [0xEF, 0xBB, 0xBF, ...utf8.encode('你好世界')]);
      final result = TextDecoder.decode(bytes);
      expect(result.content, '你好世界');
      expect(result.encoding, DetectedEncoding.utf8Bom);
    });

    test('GBK 编码自动识别', () {
      // 用 GbkCodec 编码出非 UTF-8 字节流
      final gbkBytes = const GbkCodec().encode('你好世界');
      final result =
          TextDecoder.decode(Uint8List.fromList(gbkBytes));
      expect(result.content, '你好世界');
      expect(result.encoding, DetectedEncoding.gbk);
    });

    test('UTF-16 LE 带 BOM', () {
      final text = '你好';
      final units = text.codeUnits;
      final body = <int>[];
      for (final u in units) {
        body.add(u & 0xFF);
        body.add((u >> 8) & 0xFF);
      }
      final bytes = Uint8List.fromList([0xFF, 0xFE, ...body]);
      final result = TextDecoder.decode(bytes);
      expect(result.content, text);
      expect(result.encoding, DetectedEncoding.utf16Le);
    });
  });
}
