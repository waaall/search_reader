// 编码回归：正常输入保持无损，BOM 明确的损坏输入保留可读正文并报告告警。
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/encoding/text_decoder.dart';

void main() {
  group('TextDecoder', () {
    test('GB18030 四字节字符与双字节中文混合解码无损', () {
      final result = TextDecoder.decode(
        Uint8List.fromList([0x41, 0xC4, 0xE3, 0x95, 0x32, 0x82, 0x36, 0x42]),
      );
      expect(result.content, 'A你𠀀B');
      expect(result.encoding, DetectedEncoding.gb18030);
      expect(result.hadErrors, isFalse);
    });

    test('UTF-8 BOM 中坏字节只影响局部，不改变其余正文编码', () {
      final result = TextDecoder.decode(
        Uint8List.fromList([
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode('前文你好'),
          0xFF,
          ...utf8.encode('后文世界'),
        ]),
      );
      expect(result.content, '前文你好�后文世界');
      expect(result.encoding, DetectedEncoding.utf8Bom);
      expect(result.hadErrors, isTrue);
    });

    test('原文合法的替换字符不能被误报为有损解码', () {
      final result = TextDecoder.decode(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('已有�字符')]),
      );
      expect(result.content, '已有�字符');
      expect(result.hadErrors, isFalse);
    });

    for (final littleEndian in [true, false]) {
      for (final text in ['\uFEFF正文', '\uFEFF\uFEFF🙂�正文', '正常🙂正文']) {
        test('合法 UTF-16 不因正文 U+FEFF 或代理对而误报：$littleEndian，$text', () {
          final result = TextDecoder.decode(
            _utf16Bytes(text, littleEndian: littleEndian),
          );
          expect(result.content, text);
          expect(result.hadErrors, isFalse);
        });
      }

      test('UTF-16 开头 U+FEFF 不掩盖其后的孤立代理项：$littleEndian', () {
        final result = TextDecoder.decode(
          _utf16Bytes(
            '\uFEFF${String.fromCharCode(0xD800)}尾',
            littleEndian: littleEndian,
          ),
        );
        expect(result.content, '\uFEFF�尾');
        expect(result.hadErrors, isTrue);
      });

      test('UTF-16 损坏尾字节和孤立代理项可以局部恢复：$littleEndian', () {
        final units = [0x4F60, 0xD800, 0x597D];
        final bytes = <int>[
          if (littleEndian) ...[0xFF, 0xFE] else ...[0xFE, 0xFF],
          for (final unit in units)
            if (littleEndian) ...[
              unit & 0xFF,
              unit >> 8,
            ] else ...[
              unit >> 8,
              unit & 0xFF,
            ],
          0x41,
        ];
        final result = TextDecoder.decode(Uint8List.fromList(bytes));
        expect(result.content, '你�好�');
        expect(result.hadErrors, isTrue);
        expect(utf8.decode(utf8.encode(result.content)), result.content);
      });
    }

    test('传统编码损坏回退会明确上报而不是静默替换', () {
      final result = TextDecoder.decode(
        Uint8List.fromList([0xC4, 0xE3, 0xFF, 0x41]),
      );
      expect(result.content, '你�A');
      expect(result.hadErrors, isTrue);
    });
    test('UTF-8 无 BOM', () {
      final bytes = Uint8List.fromList(utf8.encode('你好世界'));
      final result = TextDecoder.decode(bytes);
      expect(result.content, '你好世界');
      expect(result.encoding, DetectedEncoding.utf8);
    });

    test('UTF-8 带 BOM', () {
      final bytes = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('你好世界'),
      ]);
      final result = TextDecoder.decode(bytes);
      expect(result.content, '你好世界');
      expect(result.encoding, DetectedEncoding.utf8Bom);
    });

    test('GBK 编码自动识别', () {
      // 用 GbkCodec 编码出非 UTF-8 字节流
      final gbkBytes = const GbkCodec().encode('你好世界');
      final result = TextDecoder.decode(Uint8List.fromList(gbkBytes));
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

Uint8List _utf16Bytes(String text, {required bool littleEndian}) {
  return Uint8List.fromList([
    if (littleEndian) ...[0xFF, 0xFE] else ...[0xFE, 0xFF],
    for (final unit in text.codeUnits)
      if (littleEndian) ...[
        unit & 0xFF,
        unit >> 8,
      ] else ...[
        unit >> 8,
        unit & 0xFF,
      ],
  ]);
}
