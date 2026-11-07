// UTF-8 内容解码：保留开头的 U+FEFF，避免正文片段被再次当成独立文件剥离 BOM。
// 文件级 BOM 识别由导入层完成；此处仍严格拒绝损坏或截断的 UTF-8 序列。
import 'dart:convert';

abstract final class Utf8ContentDecoder {
  static const _bomBytes = [0xEF, 0xBB, 0xBF];
  static const _bomCharacter = '\uFEFF';

  static String decode(List<int> bytes) {
    final content = utf8.decode(bytes);
    return _startsWithBom(bytes) ? '$_bomCharacter$content' : content;
  }

  static Stream<String> decodeStream(Stream<List<int>> chunks) async* {
    // 只记录前三字节，兼容 BOM 跨块的情况，不缓存或放大正文窗口。
    final prefix = <int>[];
    final tracked = chunks.map((chunk) {
      final remaining = _bomBytes.length - prefix.length;
      if (remaining > 0) prefix.addAll(chunk.take(remaining));
      return chunk;
    });
    var hasOutput = false;
    await for (final content in tracked.transform(utf8.decoder)) {
      if (content.isEmpty) continue;
      if (!hasOutput) {
        hasOutput = true;
        if (_startsWithBom(prefix)) yield _bomCharacter;
      }
      yield content;
    }
    // 片段可能只有一个 U+FEFF；标准解码器在这种情况下不会输出正文。
    if (!hasOutput && _startsWithBom(prefix)) yield _bomCharacter;
  }

  static bool _startsWithBom(List<int> bytes) {
    if (bytes.length < _bomBytes.length) return false;
    for (var index = 0; index < _bomBytes.length; index++) {
      if (bytes[index] != _bomBytes[index]) return false;
    }
    return true;
  }
}
