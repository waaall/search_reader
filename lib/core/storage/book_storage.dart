import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../encoding/text_decoder.dart';

// 沙盒内书籍文件管理
// 路径策略：appDocs/books/<uuid>.<ext>
//   - 数据库 books.file_path 存相对路径 books/<uuid>.<ext>，避免沙盒迁移失效
class BookStorage {
  static const _booksDir = 'books';
  static const _uuid = Uuid();

  // 沙盒根目录
  static Future<Directory> _root() => getApplicationDocumentsDirectory();

  // 拷贝外部文件到沙盒，返回相对路径（用于持久化）
  static Future<String> importFromExternal(String externalPath) async {
    final root = await _root();
    final targetDir = Directory(p.join(root.path, _booksDir));
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }
    final ext = p.extension(externalPath); // 含点，如 ".txt"
    final fileName = '${_uuid.v4()}$ext';
    final targetPath = p.join(targetDir.path, fileName);
    await File(externalPath).copy(targetPath);
    return p.join(_booksDir, fileName);
  }

  // 把任意文本写入沙盒（utf-8 编码），返回相对路径
  // 用于 epub 等需要先解析再持久化的格式：原 epub 不存，只存抽取后的纯文本
  // reader 后续可统一按 txt 流程读取
  static Future<String> writeTextFile(String content) async {
    final root = await _root();
    final targetDir = Directory(p.join(root.path, _booksDir));
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }
    final fileName = '${_uuid.v4()}.txt';
    final targetPath = p.join(targetDir.path, fileName);
    await File(targetPath).writeAsString(content);
    return p.join(_booksDir, fileName);
  }

  // 相对路径 → 绝对路径
  static Future<String> resolveAbsolute(String relativePath) async {
    final root = await _root();
    return p.join(root.path, relativePath);
  }

  // 读取沙盒书籍文件并解码为统一换行（\n）的纯文本
  // 字符位置（chapters.start_char/end_char、阅读进度、书签）都基于此文本
  // Reader 与 Search 共用此入口，保证字符坐标一致
  static Future<String> readFullText(String relativePath) async {
    final abs = await resolveAbsolute(relativePath);
    final bytes = await File(abs).readAsBytes();
    final decoded = TextDecoder.decode(bytes);
    return decoded.content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  // 删除沙盒中的文件（数据库行由调用方处理）
  static Future<void> deleteFile(String relativePath) async {
    final abs = await resolveAbsolute(relativePath);
    final f = File(abs);
    if (await f.exists()) {
      await f.delete();
    }
  }

  // 清空整个沙盒书籍目录
  // 数据库 drop & recreate 迁移会丢弃所有书记录，需同步删除实体文件，
  // 否则旧书文件成孤儿永久占盘
  static Future<void> purgeAll() async {
    final root = await _root();
    final dir = Directory(p.join(root.path, _booksDir));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
