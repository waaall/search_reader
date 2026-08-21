// 导入流程编排：解析源文件、暂存、原子写库并发布正式文件。
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/db/application_data_operation_coordinator.dart';
import '../../core/db/daos.dart';
import '../../core/db/text_index_worker.dart';
import '../../core/encoding/text_decoder.dart';
import '../../core/parser/book_import_worker.dart';
import '../../core/parser/import_limits.dart';
import '../../core/storage/book_storage.dart';
import '../../domain/book.dart';
import 'import_progress.dart';

// 导入流程编排：worker 解析正文 → 暂存规范化文本 → 短事务写元数据 → 分批建立全文索引。
class ImporterService {
  ImporterService({
    BookImportDao? importDao,
    BookStorage? storage,
    ImportLimits? limits,
  }) : _importDao = importDao ?? BookImportDao(),
       _storage = storage ?? BookStorage.shared,
       _limits = limits ?? ImportLimits.defaults;

  final BookImportDao _importDao;
  final BookStorage _storage;
  final ImportLimits _limits;

  // 导入单个文件
  // [externalPath] 来自 file_picker 的原始路径
  // 流程：两种格式都由 worker 生成 UTF-8 正文，随后统一执行索引、原子发布和恢复日志清理。
  Future<ImportResult> importFile(
    String externalPath, {
    void Function(ImportPhase phase)? onProgress,
  }) {
    return ApplicationDataOperationCoordinator.run(
      () => _importFile(externalPath, onProgress: onProgress),
    );
  }

  Future<ImportResult> _importFile(
    String externalPath, {
    void Function(ImportPhase phase)? onProgress,
  }) async {
    final ext = p.extension(externalPath).toLowerCase();
    StagedBookFile? stagedFile;
    int? pendingBookId;
    try {
      if (!isSupportedBookFile(externalPath)) {
        throw ImportException.unsupportedFormat(ext);
      }

      onProgress?.call(ImportPhase.parsing);
      // 先分配临时正文路径，再由 worker 在后台 isolate 中解析并写入 UTF-8。
      stagedFile = await _storage.allocateNormalizedStagedFile();
      final stagedAbsolute = await _storage.resolveAbsolute(
        stagedFile.stagedPath,
      );
      final manifest = await BookImportWorker.run(
        inputPath: externalPath,
        outputPath: stagedAbsolute,
        extension: ext,
        limits: _limits,
      );

      onProgress?.call(ImportPhase.indexing);
      final title = _titleFromPath(externalPath);
      final indexWorker = TextIndexWorker();
      late final Book book;
      try {
        book = await _importDao.createPendingImportFromManifest(
          title: title,
          stagedPath: stagedFile.stagedPath,
          targetPath: stagedFile.targetPath,
          manifest: manifest,
          readChapter: (chapter) => _storage.readTextRange(
            stagedFile!.stagedPath,
            startByte: chapter.startByte,
            endByte: chapter.endByte,
          ),
          buildIndex: (title, content) =>
              indexWorker.tokenize(title: title, content: content),
        );
      } finally {
        await indexWorker.close();
      }
      pendingBookId = book.id;

      // 数据库事务提交后再原子发布文件，最后删除恢复日志使书籍对查询可见。
      await _storage.finalizeStagedFile(stagedFile);
      await _importDao.markImportComplete(book.id);

      onProgress?.call(ImportPhase.done);
      return ImportResult(
        bookId: book.id,
        title: book.title,
        chapterCount: manifest.chapters.length,
        totalChars: manifest.totalChars,
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
// 对外保留旧常量名称，实际策略统一由 ImportLimits 管理。
const int kMaxTxtBytes = ImportLimits.defaultMaxTxtBytes;
const int kMaxEpubBytes = ImportLimits.defaultMaxEpubBytes;

// 取文件大小失败时（沙盒权限边界、路径异常等）不在这一步拦截
// 让导入流程自己暴露真实错误，避免把"读不到"误报为"超大"
Future<bool> isWithinSizeLimit(String path) async {
  try {
    final len = await File(path).length();
    final ext = p.extension(path).toLowerCase();
    final limit = ImportLimits.defaults.limitForExtension(ext);
    return len <= limit;
  } catch (_) {
    return true;
  }
}
