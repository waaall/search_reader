// 规范化正文写入器：边写 UTF-8 正文边累计字符和字节坐标，避免再次扫描整本书。
import 'dart:convert';
import 'dart:io';

class NormalizedTextWriter {
  NormalizedTextWriter._(this._file);

  final RandomAccessFile _file;
  int charCount = 0;
  int byteCount = 0;
  bool _closed = false;

  static Future<NormalizedTextWriter> open(String path) async {
    final file = await File(path).open(mode: FileMode.write);
    return NormalizedTextWriter._(file);
  }

  Future<void> write(String text) async {
    if (text.isEmpty) return;
    final bytes = utf8.encode(text);
    await _file.writeFrom(bytes);
    charCount += text.length;
    byteCount += bytes.length;
  }

  Future<void> flushAndClose() async {
    if (_closed) return;
    try {
      await _file.flush();
    } finally {
      await close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _file.close();
  }
}
