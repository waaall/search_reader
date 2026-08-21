// 沙盒书籍文件管理：通过临时文件发布协议隔离未完成导入。
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

typedef StorageRootProvider = Future<Directory> Function();

// 文件检查使用三态结果，避免把权限或临时 I/O 错误误判成文件不存在。
enum BookFileAvailability { available, missing, unavailable }

class StagedBookFile {
  final String stagedPath;
  final String targetPath;

  const StagedBookFile({required this.stagedPath, required this.targetPath});
}

// 路径策略：
// - 正式文件：appDocs/books/<uuid>.txt（统一规范化为 UTF-8）
// - 临时文件：appDocs/books/.staging/<uuid>.<ext>.pending
// - 数据库 books.file_path 只保存正式文件的相对路径
class BookStorage {
  BookStorage({StorageRootProvider? rootProvider})
    : _rootProvider = rootProvider ?? getApplicationDocumentsDirectory;

  static final BookStorage shared = BookStorage();

  static const _booksDir = 'books';
  static const _stagingDir = '.staging';
  static const _pendingSuffix = '.pending';
  static const _uuid = Uuid();

  final StorageRootProvider _rootProvider;

  Future<Directory> _root() => _rootProvider();

  // 把外部文件完整写入临时区；数据库提交前不会出现在正式目录。
  Future<StagedBookFile> stageExternalFile(String externalPath) async {
    final ext = p.extension(externalPath);
    final paths = await _allocatePaths(ext);
    final stagedAbsolute = await resolveAbsolute(paths.stagedPath);
    try {
      await File(externalPath).copy(stagedAbsolute);

      // 尽量把复制结果刷到磁盘，再允许数据库事务引用它。
      final handle = await File(stagedAbsolute).open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      return paths;
    } catch (_) {
      try {
        await File(stagedAbsolute).delete();
      } catch (_) {}
      rethrow;
    }
  }

  // epub 等格式先抽取为纯文本，再将 utf-8 内容写入临时区。
  Future<StagedBookFile> stageTextFile(String content) async {
    final paths = await _allocatePaths('.txt');
    final stagedAbsolute = await resolveAbsolute(paths.stagedPath);
    try {
      await File(stagedAbsolute).writeAsString(content, flush: true);
      return paths;
    } catch (_) {
      try {
        await File(stagedAbsolute).delete();
      } catch (_) {}
      rethrow;
    }
  }

  // 为 worker 预留规范化正文文件路径；实际写入由 worker 在后台 isolate 完成。
  Future<StagedBookFile> allocateNormalizedStagedFile() {
    return _allocatePaths('.txt');
  }

  Future<StagedBookFile> _allocatePaths(String extension) async {
    final root = await _root();
    final stagingDirectory = Directory(
      p.join(root.path, _booksDir, _stagingDir),
    );
    await stagingDirectory.create(recursive: true);

    final fileName = '${_uuid.v4()}$extension';
    return StagedBookFile(
      stagedPath: p.join(_booksDir, _stagingDir, '$fileName$_pendingSuffix'),
      targetPath: p.join(_booksDir, fileName),
    );
  }

  // 同一沙盒卷内 rename 是原子发布；重复执行可恢复“已改名但未清日志”的崩溃点。
  Future<void> finalizeStagedFile(StagedBookFile stagedFile) async {
    final stagedAbsolute = await resolveAbsolute(stagedFile.stagedPath);
    final targetAbsolute = await resolveAbsolute(stagedFile.targetPath);
    final staged = File(stagedAbsolute);
    final target = File(targetAbsolute);

    if (await target.exists()) {
      if (await staged.exists()) await staged.delete();
      return;
    }
    if (!await staged.exists()) {
      throw FileSystemException('导入临时文件不存在', stagedAbsolute);
    }
    await target.parent.create(recursive: true);
    await staged.rename(targetAbsolute);
  }

  Future<void> discardStagedFile(StagedBookFile stagedFile) async {
    await deleteFile(stagedFile.stagedPath);
  }

  // 相对路径 → 绝对路径。
  Future<String> resolveAbsolute(String relativePath) async {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized) || !p.isWithin(_booksDir, normalized)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        '路径必须位于 books/ 内',
      );
    }
    final root = await _root();
    return p.join(root.path, normalized);
  }

  Future<bool> exists(String relativePath) async {
    final absolute = await resolveAbsolute(relativePath);
    return File(absolute).exists();
  }

  // 恢复流程只在明确得到 notFound 时删除数据库记录；路径或 I/O 异常均视为暂不可确认。
  Future<BookFileAvailability> inspectAvailability(String relativePath) async {
    try {
      final absolute = await resolveAbsolute(relativePath);
      final stat = await File(absolute).stat();
      if (stat.type == FileSystemEntityType.file) {
        return BookFileAvailability.available;
      }
      if (stat.type == FileSystemEntityType.notFound) {
        return BookFileAvailability.missing;
      }
      // 目录、链接等非普通文件不应触发不可逆的数据删除，交给后续人工处理。
      developer.log(
        '书籍路径不是普通文件，保留数据库记录：$relativePath',
        name: 'search_reader.book_storage',
      );
      return BookFileAvailability.unavailable;
    } catch (error, stackTrace) {
      developer.log(
        '检查书籍文件状态失败，保留数据库记录：$relativePath',
        name: 'search_reader.book_storage',
        error: error,
        stackTrace: stackTrace,
      );
      return BookFileAvailability.unavailable;
    }
  }

  // 正文统一为 UTF-8，可按字节范围读取单个章节，避免加载整本书。
  Future<String> readTextRange(
    String relativePath, {
    required int startByte,
    required int endByte,
  }) async {
    if (startByte < 0 || endByte < startByte) {
      throw ArgumentError('正文字节范围无效：[$startByte, $endByte)');
    }
    final absolute = await resolveAbsolute(relativePath);
    final file = File(absolute);
    final length = await file.length();
    if (endByte > length) {
      throw FileSystemException('正文字节范围超出文件长度', absolute);
    }

    final handle = await file.open();
    try {
      await handle.setPosition(startByte);
      final bytes = <int>[];
      // 常规文件通常一次读完，但 RandomAccessFile 允许返回短读；循环读取避免索引缺尾。
      await for (final chunk in _readByteChunks(
        handle,
        endByte - startByte,
        64 * 1024,
        absolute,
      )) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } finally {
      await handle.close();
    }
  }

  // 搜索摘要按固定大小的 UTF-8 字节块读取，避免为寻找命中位置一次性加载整章。
  Stream<String> readUtf8RangeChunks(
    String relativePath, {
    required int startByte,
    required int endByte,
    int chunkBytes = 64 * 1024,
  }) async* {
    if (startByte < 0 || endByte < startByte) {
      throw ArgumentError('正文字节范围无效：[$startByte, $endByte)');
    }
    if (chunkBytes <= 0) {
      throw ArgumentError.value(chunkBytes, 'chunkBytes', '必须大于 0');
    }
    final absolute = await resolveAbsolute(relativePath);
    final file = File(absolute);
    final length = await file.length();
    if (endByte > length) {
      throw FileSystemException('正文字节范围超出文件长度', absolute);
    }

    final handle = await file.open();
    try {
      await handle.setPosition(startByte);
      yield* _readByteChunks(
        handle,
        endByte - startByte,
        chunkBytes,
        absolute,
      ).transform(utf8.decoder);
    } finally {
      await handle.close();
    }
  }

  Stream<List<int>> _readByteChunks(
    RandomAccessFile handle,
    int length,
    int chunkBytes,
    String absolute,
  ) async* {
    var remaining = length;
    while (remaining > 0) {
      final chunk = await handle.read(
        remaining < chunkBytes ? remaining : chunkBytes,
      );
      if (chunk.isEmpty) {
        throw FileSystemException('读取正文字节范围时提前遇到文件尾', absolute);
      }
      remaining -= chunk.length;
      yield chunk;
    }
  }

  // 所有书籍都必须具备 UTF-8 字节范围；范围不完整直接报错，避免隐式整本读取。
  Future<String> readChapterText(
    String relativePath, {
    required int startChar,
    required int endChar,
    required int startByte,
    required int endByte,
  }) async {
    if (startByte < 0 || endByte < startByte) {
      throw StateError('章节缺少有效的 UTF-8 字节范围');
    }
    final text = await readTextRange(
      relativePath,
      startByte: startByte,
      endByte: endByte,
    );
    if (text.length != endChar - startChar) {
      throw StateError('章节字符范围与 UTF-8 字节范围不一致');
    }
    return text;
  }

  Future<void> deleteFile(String relativePath) async {
    final absolute = await resolveAbsolute(relativePath);
    final file = File(absolute);
    if (await file.exists()) await file.delete();
  }

  // 仅清理未被 books.file_path 引用的正式直属文件；目录和链接一律保留。
  Future<void> deleteUnreferencedFiles(Set<String> referencedPaths) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, _booksDir));
    if (!await directory.exists()) return;

    final normalizedReferences = referencedPaths.map(p.normalize).toSet();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = p.normalize(
        p.relative(entity.path, from: root.path),
      );
      if (!normalizedReferences.contains(relativePath)) {
        await entity.delete();
      }
    }
  }

  // 启动恢复后清理没有 import_jobs 登记的临时文件，保留待重试任务。
  Future<void> deleteUnregisteredStagedFiles(
    Set<String> registeredPaths,
  ) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, _booksDir, _stagingDir));
    if (!await directory.exists()) return;

    final normalizedReferences = registeredPaths.map(p.normalize).toSet();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = p.normalize(
        p.relative(entity.path, from: root.path),
      );
      if (!normalizedReferences.contains(relativePath)) {
        await entity.delete();
      }
    }
  }
}
