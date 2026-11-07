// GB18030 标准边界与损坏序列回归：防止仅修复单个生僻字而遗漏其它映射。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/encoding/gb18030_decoder.dart';

void main() {
  final rangeBoundaries = <int, int>{
    0: 0x80,
    35: 0xA3,
    36: 0xA5,
    7457: 0xE7C7,
    39419: 0xFFFF,
    189000: 0x10000,
    1237575: 0x10FFFF,
  };
  for (final entry in rangeBoundaries.entries) {
    test('四字节范围边界 ${entry.key} 映射为 U+${entry.value.toRadixString(16)}', () {
      final result = Gb18030Decoder.decode(
        Uint8List.fromList(_fourBytes(entry.key)),
      );
      expect(result.content.runes.single, entry.value);
      expect(result.hadErrors, isFalse);
      expect(result.usedFourByteSequence, isTrue);
    });
  }

  for (final pointer in [39420, 188999, 1237576, 1587599]) {
    test('未映射四字节指针 $pointer 不产生非法 Unicode', () {
      final bytes = Uint8List.fromList([..._fourBytes(pointer), 0x41]);
      expect(() => Gb18030Decoder.decode(bytes), throwsFormatException);
      final result = Gb18030Decoder.decode(bytes, allowMalformed: true);
      expect(result.content, '�A');
      expect(result.hadErrors, isTrue);
    });
  }

  final malformedSequences = <List<int>, String>{
    [0x81]: '�',
    [0x81, 0x30]: '�',
    [0x81, 0x30, 0x81]: '�',
    [0x81, 0x20]: '� ',
    [0x81, 0x30, 0x20]: '�0 ',
    [0x81, 0x30, 0x81, 0x20]: '�0� ',
    [0xFF, 0x41]: '�A',
  };
  for (final entry in malformedSequences.entries) {
    test('错误序列 ${entry.key} 替换时保留后续 ASCII', () {
      final bytes = Uint8List.fromList(entry.key);
      expect(() => Gb18030Decoder.decode(bytes), throwsFormatException);
      final result = Gb18030Decoder.decode(bytes, allowMalformed: true);
      expect(result.content, entry.value);
      expect(result.hadErrors, isTrue);
    });
  }

  test('全部 23940 个双字节索引均可解码且映射未被改写', () {
    final bytes = <int>[];
    for (var first = 0x81; first <= 0xFE; first++) {
      for (var second = 0x40; second <= 0xFE; second++) {
        if (second != 0x7F) bytes.addAll([first, second]);
      }
    }
    final result = Gb18030Decoder.decode(Uint8List.fromList(bytes));
    expect(result.hadErrors, isFalse);
    expect(result.usedFourByteSequence, isFalse);
    expect(result.content.length, 23940);
    var checksum = 0x811C9DC5;
    for (final unit in result.content.codeUnits) {
      checksum = ((checksum ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    // WHATWG 2024-09-18 双字节索引按指针排列的 FNV-1a 校验值。
    expect(checksum, 0x375A6C11);
  });

  test('欧元的单字节和双字节兼容编码均可读取', () {
    final result = Gb18030Decoder.decode(
      Uint8List.fromList([0x80, 0xA2, 0xE3]),
    );
    expect(result.content, '€€');
    expect(result.hadErrors, isFalse);
  });
}

List<int> _fourBytes(int pointer) => [
  pointer ~/ 12600 + 0x81,
  (pointer % 12600) ~/ 1260 + 0x30,
  (pointer % 1260) ~/ 10 + 0x81,
  pointer % 10 + 0x30,
];
