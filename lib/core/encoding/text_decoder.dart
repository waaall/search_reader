// 文本编码识别：明确的 BOM 优先，损坏序列保留为替换字符并向导入流程报告。
import 'dart:convert';
import 'dart:typed_data';

import 'gb18030_decoder.dart';
import 'utf8_content_decoder.dart';

// 检测出的编码标签
class DetectedEncoding {
  static const utf8 = 'utf-8';
  static const utf8Bom = 'utf-8-bom';
  static const utf16Le = 'utf-16-le';
  static const utf16Be = 'utf-16-be';
  static const gbk = 'gbk';
  static const gb18030 = 'gb18030';
}

class DecodedText {
  final String content;
  final String encoding;
  final bool hadErrors;
  const DecodedText(this.content, this.encoding, {this.hadErrors = false});
}

class DecodingException implements Exception {
  final String message;
  DecodingException(this.message);
  @override
  String toString() => 'DecodingException: $message';
}

// 文本解码：BOM → UTF-8 严格 → GB18030（包含 GBK 双字节子集）。
class TextDecoder {
  // 主入口：从字节流推断编码并解码
  static DecodedText decode(Uint8List bytes) {
    // 1. BOM 检测
    final byBom = _tryDecodeByBom(bytes);
    if (byBom != null) return byBom;

    // 2. UTF-8 严格解码（不允许非法字节）
    try {
      final text = const Utf8Decoder(allowMalformed: false).convert(bytes);
      return DecodedText(text, DetectedEncoding.utf8);
    } on FormatException {
      // 落到下一个候选
    }

    // 3. 使用完整 GB18030 映射；严格失败后才允许替换，并显式上报有损转换。
    try {
      return _decodeLegacy(bytes, allowMalformed: false);
    } on FormatException {
      return _decodeLegacy(bytes, allowMalformed: true);
    }
  }

  static DecodedText _decodeLegacy(
    Uint8List bytes, {
    required bool allowMalformed,
  }) {
    final result = Gb18030Decoder.decode(bytes, allowMalformed: allowMalformed);
    return DecodedText(
      result.content,
      result.usedFourByteSequence
          ? DetectedEncoding.gb18030
          : DetectedEncoding.gbk,
      hadErrors: result.hadErrors,
    );
  }

  // BOM 头部判断
  static DecodedText? _tryDecodeByBom(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      final body = Uint8List.sublistView(bytes, 3);
      try {
        return DecodedText(utf8.decode(body), DetectedEncoding.utf8Bom);
      } on FormatException {
        // 编码已经明确，不能因一个坏字节拒绝整本书，也不能转用 GBK 破坏其余正文。
        return DecodedText(
          utf8.decode(body, allowMalformed: true),
          DetectedEncoding.utf8Bom,
          hadErrors: true,
        );
      }
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(Uint8List.sublistView(bytes, 2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(Uint8List.sublistView(bytes, 2), littleEndian: false);
    }
    return null;
  }

  // UTF-16 解码：dart:convert 没有官方 codec，手工组装码点
  static DecodedText _decodeUtf16(
    Uint8List bytes, {
    required bool littleEndian,
  }) {
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final unit = littleEndian
          ? (bytes[i + 1] << 8) | bytes[i]
          : (bytes[i] << 8) | bytes[i + 1];
      codeUnits.add(unit);
    }
    if (bytes.length.isOdd) codeUnits.add(0xFFFD);
    final raw = String.fromCharCodes(codeUnits);
    // 统一在生成字符/字节范围前替换孤立代理项，保证后续 UTF-8 存储和坐标一致。
    // 正文开头合法的 U+FEFF 必须保留，不能把 BOM 归一化误判成损坏替换。
    final text = Utf8ContentDecoder.decode(utf8.encode(raw));
    return DecodedText(
      text,
      littleEndian ? DetectedEncoding.utf16Le : DetectedEncoding.utf16Be,
      hadErrors: bytes.length.isOdd || text != raw,
    );
  }
}
