import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

// 检测出的编码标签
class DetectedEncoding {
  static const utf8 = 'utf-8';
  static const utf8Bom = 'utf-8-bom';
  static const utf16Le = 'utf-16-le';
  static const utf16Be = 'utf-16-be';
  static const gbk = 'gbk';
}

class DecodedText {
  final String content;
  final String encoding;
  const DecodedText(this.content, this.encoding);
}

class DecodingException implements Exception {
  final String message;
  DecodingException(this.message);
  @override
  String toString() => 'DecodingException: $message';
}

// 文本解码：BOM → UTF-8 严格 → GBK fallback
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

    // 3. GBK fallback（中文小说常见编码，GB18030/GBK 兼容大部分内容）
    try {
      final text = const GbkCodec(allowInvalid: false).decode(bytes);
      return DecodedText(text, DetectedEncoding.gbk);
    } catch (_) {
      // 再宽松一次（允许个别非法字符替换为占位符）
      try {
        final text = const GbkCodec(allowInvalid: true).decode(bytes);
        return DecodedText(text, DetectedEncoding.gbk);
      } catch (e) {
        throw DecodingException('无法识别文件编码：$e');
      }
    }
  }

  // BOM 头部判断
  static DecodedText? _tryDecodeByBom(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      final text = utf8.decode(bytes.sublist(3));
      return DecodedText(text, DetectedEncoding.utf8Bom);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final text = _decodeUtf16(bytes.sublist(2), littleEndian: true);
      return DecodedText(text, DetectedEncoding.utf16Le);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final text = _decodeUtf16(bytes.sublist(2), littleEndian: false);
      return DecodedText(text, DetectedEncoding.utf16Be);
    }
    return null;
  }

  // UTF-16 解码：dart:convert 没有官方 codec，手工组装码点
  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    if (bytes.length.isOdd) {
      throw DecodingException('UTF-16 字节数不是偶数');
    }
    final codeUnits = <int>[];
    for (var i = 0; i < bytes.length; i += 2) {
      final unit = littleEndian
          ? (bytes[i + 1] << 8) | bytes[i]
          : (bytes[i] << 8) | bytes[i + 1];
      codeUnits.add(unit);
    }
    return String.fromCharCodes(codeUnits);
  }
}
