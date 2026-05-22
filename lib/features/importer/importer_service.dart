import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/db/daos.dart';
import '../../core/encoding/text_decoder.dart';
import '../../core/parser/book_format.dart';
import '../../core/parser/epub_parser.dart';
import '../../core/parser/txt_parser.dart';
import '../../core/storage/book_storage.dart';
import 'import_progress.dart';

// 导入流程编排：根据格式分发 parser → 持久化文本到沙盒 → 写入数据库 + FTS5 索引
class ImporterService {
  ImporterService({
    TxtParser? txtParser,
    EpubParser? epubParser,
    BookDao? bookDao,
    ChapterDao? chapterDao,
  }) : _txtParser = txtParser ?? TxtParser(),
       _epubParser = epubParser ?? EpubParser(),
       _bookDao = bookDao ?? BookDao(),
       _chapterDao = chapterDao ?? ChapterDao();

  final TxtParser _txtParser;
  final EpubParser _epubParser;
  final BookDao _bookDao;
  final ChapterDao _chapterDao;

  // 按扩展名选择 parser；不支持的格式抛 ImportException
  BookFormatParser _pickParser(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.txt':
        return _txtParser;
      case '.epub':
        return _epubParser;
      default:
        throw ImportException.unsupportedFormat(ext);
    }
  }

  // 导入单个文件
  // [externalPath] 来自 file_picker 的原始路径
  // 流程：
  //   - txt：先 copy 原文件到沙盒 → 解析章节（reader 读盘时再按原编码解码）
  //   - epub：直接解析外部文件 → 把抽取后的纯文本写入沙盒 .txt（reader 走通用 txt 路径）
  Future<ImportResult> importFile(
    String externalPath, {
    void Function(ImportPhase phase)? onProgress,
  }) async {
    final ext = p.extension(externalPath).toLowerCase();
    String? sandboxRelativePath;
    int? insertedBookId; // 已写入的 books 行 id：失败时需连带回滚
    try {
      final parser = _pickParser(externalPath);

      onProgress?.call(ImportPhase.parsing);
      // epub 体积可能远大于解析后的纯文本，先解析再决定写入内容
      final ParsedBook parsed;
      if (ext == '.epub') {
        parsed = await parser.parse(externalPath);
        onProgress?.call(ImportPhase.copying);
        sandboxRelativePath = await BookStorage.writeTextFile(parsed.fullText);
      } else {
        onProgress?.call(ImportPhase.copying);
        sandboxRelativePath = await BookStorage.importFromExternal(
          externalPath,
        );
        final absPath = await BookStorage.resolveAbsolute(sandboxRelativePath);
        parsed = await parser.parse(absPath);
      }

      onProgress?.call(ImportPhase.indexing);
      final title = _titleFromPath(externalPath);
      final book = await _bookDao.insert(
        title: title,
        filePath: sandboxRelativePath,
        encoding: parsed.encoding,
        totalChars: parsed.totalChars,
      );
      insertedBookId = book.id;
      await _chapterDao.insertAll(book.id, parsed.chapters);

      onProgress?.call(ImportPhase.done);
      return ImportResult(
        bookId: book.id,
        title: book.title,
        chapterCount: parsed.chapters.length,
        totalChars: parsed.totalChars,
      );
    } on DecodingException catch (e) {
      await _rollback(sandboxRelativePath, insertedBookId);
      throw ImportException.decodingFailed(e);
    } on ImportException {
      rethrow;
    } catch (e) {
      await _rollback(sandboxRelativePath, insertedBookId);
      throw ImportException.unexpected(e);
    }
  }

  // 导入失败回滚：删掉已写入的 books 行（级联清章节与 FTS）与沙盒文件
  // 章节索引失败时，books 行已提交、insertAll 事务已回滚，此时只删 books 行即可
  // 回滚自身的异常吞掉：避免掩盖真正的导入失败原因
  Future<void> _rollback(String? sandboxRelativePath, int? bookId) async {
    if (bookId != null) {
      try {
        await _bookDao.delete(bookId);
      } catch (_) {}
    }
    if (sandboxRelativePath != null) {
      await BookStorage.deleteFile(sandboxRelativePath);
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

// 校验文件是否为支持的格式
bool isSupportedBookFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return ext == '.txt' || ext == '.epub';
}

// 校验文件大小是否在合理范围
// txt 上限 10MB；epub 含图片资源通常更大，上限 50MB
const int kMaxTxtBytes = 10 * 1024 * 1024;
const int kMaxEpubBytes = 50 * 1024 * 1024;

// 取文件大小失败时（沙盒权限边界、路径异常等）不在这一步拦截
// 让导入流程自己暴露真实错误，避免把"读不到"误报为"超大"
Future<bool> isWithinSizeLimit(String path) async {
  try {
    final len = await File(path).length();
    final ext = p.extension(path).toLowerCase();
    final limit = ext == '.epub' ? kMaxEpubBytes : kMaxTxtBytes;
    return len <= limit;
  } catch (_) {
    return true;
  }
}
