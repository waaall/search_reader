// 导入流程编排：解析源文件、暂存、原子写库并发布正式文件。
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
    BookImportDao? importDao,
    BookStorage? storage,
  }) : _txtParser = txtParser ?? TxtParser(),
       _epubParser = epubParser ?? EpubParser(),
       _importDao = importDao ?? BookImportDao(),
       _storage = storage ?? BookStorage.shared;

  final TxtParser _txtParser;
  final EpubParser _epubParser;
  final BookImportDao _importDao;
  final BookStorage _storage;

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
  //   - txt：解析源文件 → 临时区复制原始字节，保留编码
  //   - epub：解析源文件 → 临时区写入抽取后的 utf-8 纯文本
  //   - 两者随后统一执行数据库事务、原子 rename 和恢复日志清理
  Future<ImportResult> importFile(
    String externalPath, {
    void Function(ImportPhase phase)? onProgress,
  }) async {
    final ext = p.extension(externalPath).toLowerCase();
    StagedBookFile? stagedFile;
    int? pendingBookId;
    try {
      final parser = _pickParser(externalPath);

      onProgress?.call(ImportPhase.parsing);
      // 先解析外部源文件，成功后才向沙盒临时区写入，减少无效文件。
      final parsed = await parser.parse(externalPath);

      onProgress?.call(ImportPhase.copying);
      if (ext == '.epub') {
        stagedFile = await _storage.stageTextFile(parsed.fullText);
      } else {
        stagedFile = await _storage.stageExternalFile(externalPath);
      }

      onProgress?.call(ImportPhase.indexing);
      final title = _titleFromPath(externalPath);
      final book = await _importDao.createPendingImport(
        title: title,
        stagedPath: stagedFile.stagedPath,
        targetPath: stagedFile.targetPath,
        parsed: parsed,
      );
      pendingBookId = book.id;

      // 数据库事务提交后再原子发布文件，最后删除恢复日志使书籍对查询可见。
      await _storage.finalizeStagedFile(stagedFile);
      await _importDao.markImportComplete(book.id);

      onProgress?.call(ImportPhase.done);
      return ImportResult(
        bookId: book.id,
        title: book.title,
        chapterCount: parsed.chapters.length,
        totalChars: parsed.totalChars,
      );
    } on DecodingException catch (e) {
      await _rollback(stagedFile, pendingBookId);
      throw ImportException.decodingFailed(e);
    } on ImportException {
      await _rollback(stagedFile, pendingBookId);
      rethrow;
    } catch (e) {
      await _rollback(stagedFile, pendingBookId);
      throw ImportException.unexpected(e);
    }
  }

  // 运行期失败尽量撤销两侧；若数据库撤销失败则保留文件和日志供启动恢复。
  Future<void> _rollback(StagedBookFile? stagedFile, int? bookId) async {
    var databaseWasRolledBack = bookId == null;
    if (bookId != null) {
      try {
        await _importDao.cancelPendingImport(bookId);
        databaseWasRolledBack = true;
      } catch (_) {}
    }
    if (stagedFile != null && databaseWasRolledBack) {
      try {
        await _storage.discardStagedFile(stagedFile);
        await _storage.deleteFile(stagedFile.targetPath);
      } catch (_) {}
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
