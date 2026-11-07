// GB18030 解码器：按 WHATWG 状态机处理一、二、四字节序列，全部映射离线提供。
// 不依赖系统字符集或原生插件，导入 worker 在各平台使用相同结果。
import 'dart:convert';
import 'dart:typed_data';

part 'gb18030_data.dart';

class Gb18030DecodingResult {
  final String content;
  final bool hadErrors;
  final bool usedFourByteSequence;

  const Gb18030DecodingResult({
    required this.content,
    required this.hadErrors,
    required this.usedFourByteSequence,
  });
}

abstract final class Gb18030Decoder {
  static final _twoByteIndex = ByteData.sublistView(
    base64Decode(_gb18030TwoByteBase64),
  );

  static Gb18030DecodingResult decode(
    Uint8List bytes, {
    bool allowMalformed = false,
  }) {
    final output = StringBuffer();
    var first = 0;
    var second = 0;
    var third = 0;
    var hadErrors = false;
    var usedFourByteSequence = false;

    void reportError(int offset) {
      if (!allowMalformed) {
        throw FormatException('无效的 GB18030 字节序列', bytes, offset);
      }
      hadErrors = true;
      output.writeCharCode(0xFFFD);
    }

    for (var offset = 0; offset < bytes.length; offset++) {
      final byte = bytes[offset];
      if (third != 0) {
        if (byte < 0x30 || byte > 0x39) {
          // 重放后三个字节，不能因一个错误首字节吞掉后面的 ASCII 或正文。
          first = second = third = 0;
          reportError(offset - 3);
          offset -= 3;
          continue;
        }
        final pointer =
            (first - 0x81) * 12600 +
            (second - 0x30) * 1260 +
            (third - 0x81) * 10 +
            byte -
            0x30;
        first = second = third = 0;
        final codePoint = _fourByteCodePoint(pointer);
        if (codePoint == null) {
          reportError(offset - 3);
        } else {
          usedFourByteSequence = true;
          output.writeCharCode(codePoint);
        }
        continue;
      }
      if (second != 0) {
        if (byte >= 0x81 && byte <= 0xFE) {
          third = byte;
        } else {
          first = second = 0;
          reportError(offset - 2);
          offset -= 2;
        }
        continue;
      }
      if (first != 0) {
        if (byte >= 0x30 && byte <= 0x39) {
          second = byte;
          continue;
        }
        final leading = first;
        first = 0;
        if ((byte >= 0x40 && byte <= 0x7E) || (byte >= 0x80 && byte <= 0xFE)) {
          final pointer =
              (leading - 0x81) * 190 + byte - (byte < 0x7F ? 0x40 : 0x41);
          output.writeCharCode(
            _twoByteIndex.getUint16(pointer * 2, Endian.little),
          );
        } else {
          reportError(offset - 1);
          if (byte <= 0x7F) offset--;
        }
        continue;
      }
      if (byte <= 0x7F) {
        output.writeCharCode(byte);
      } else if (byte == 0x80) {
        output.writeCharCode(0x20AC);
      } else if (byte >= 0x81 && byte <= 0xFE) {
        first = byte;
      } else {
        reportError(offset);
      }
    }
    if (first != 0 || second != 0 || third != 0) {
      reportError(bytes.length);
    }
    return Gb18030DecodingResult(
      content: output.toString(),
      hadErrors: hadErrors,
      usedFourByteSequence: usedFourByteSequence,
    );
  }

  static int? _fourByteCodePoint(int pointer) {
    if ((pointer > 39419 && pointer < 189000) || pointer > 1237575) {
      return null;
    }
    // 标准规定的历史映射例外，不是针对输入数据的特殊处理。
    if (pointer == 7457) return 0xE7C7;
    var low = 0;
    var high = _gb18030Ranges.length;
    while (low + 1 < high) {
      final mid = (low + high) >> 1;
      if (_gb18030Ranges[mid].$1 <= pointer) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final (startPointer, startCodePoint) = _gb18030Ranges[low];
    return startCodePoint + pointer - startPointer;
  }
}
