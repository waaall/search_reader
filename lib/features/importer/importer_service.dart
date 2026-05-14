import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/db/daos.dart';
import '../../core/encoding/text_decoder.dart';
import '../../core/parser/txt_parser.dart';
import '../../core/storage/book_storage.dart';
import 'import_progress.dart';

// 导入流程编排：复制文件 → 解析章节 → 写入数据库 + FTS5 索引
class ImporterService {
  ImporterService({TxtParser? parser, BookDao? bookDao, ChapterDao? chapterDao})
      : _parser = parser ?? TxtParser(),
        _bookDao = bookDao ?? BookDao(),
        _chapterDao = chapterDao ?? ChapterDao();

  final TxtParser _parser;
  final BookDao _bookDao;
  final ChapterDao _chapterDao;

  // 导入单个文件
  // [externalPath] 来自 file_picker 的原始路径
  Future<ImportResult> importFile(
    String externalPath, {
    void Function(ImportPhase phase)? onProgress,
  }) async {
    String? sandboxRelativePath;
    try {
      onProgress?.call(ImportPhase.copying);
      sandboxRelativePath = await BookStorage.importFromExternal(externalPath);

      onProgress?.call(ImportPhase.parsing);
      final absPath = await BookStorage.resolveAbsolute(sandboxRelativePath);
      final parsed = await _parser.parse(absPath);

      onProgress?.call(ImportPhase.indexing);
      final title = _titleFromPath(externalPath);
      final book = await _bookDao.insert(
        title: title,
        filePath: sandboxRelativePath,
        encoding: parsed.encoding,
        totalChars: parsed.totalChars,
      );
      await _chapterDao.insertAll(book.id, parsed.chapters);

      onProgress?.call(ImportPhase.done);
      return ImportResult(
        bookId: book.id,
        title: book.title,
        chapterCount: parsed.chapters.length,
        totalChars: parsed.totalChars,
      );
    } on DecodingException catch (e) {
      // 沙盒文件已经写入，需要回滚
      if (sandboxRelativePath != null) {
        await BookStorage.deleteFile(sandboxRelativePath);
      }
      throw ImportException(e.message);
    } catch (e) {
      if (sandboxRelativePath != null) {
        await BookStorage.deleteFile(sandboxRelativePath);
      }
      throw ImportException('导入失败：$e');
    }
  }

  // 文件名 → 默认书名（去扩展名 + 去掉常见无意义后缀）
  String _titleFromPath(String path) {
    var name = p.basenameWithoutExtension(path);
    // 去掉「(完结)」「[txt]」之类常见标注
    name = name.replaceAll(RegExp(r'[\[\(（【].*?[\]\)）】]'), '').trim();
    if (name.isEmpty) name = '未命名';
    return name;
  }
}

// 校验文件是否为支持的格式（MVP 只支持 txt）
bool isSupportedBookFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return ext == '.txt';
}

// 校验文件大小是否在合理范围（MVP 上限 10MB）
const int kMaxImportBytes = 10 * 1024 * 1024;
Future<bool> isWithinSizeLimit(String path) async {
  final f = File(path);
  if (!await f.exists()) return false;
  final len = await f.length();
  return len <= kMaxImportBytes;
}
