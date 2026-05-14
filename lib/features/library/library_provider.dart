import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../core/storage/book_storage.dart';
import '../../domain/book.dart';
import '../importer/import_progress.dart';
import '../importer/importer_service.dart';

// 书架状态：所有书 + 当前导入进度 + 多选状态
class LibraryState {
  final List<Book> books;
  final ImportPhase? importing; // null 表示当前没有导入中
  final String? error;
  final bool selectionMode; // 是否处于多选模式
  final Set<int> selectedIds; // 已选中的书籍 id

  const LibraryState({
    this.books = const [],
    this.importing,
    this.error,
    this.selectionMode = false,
    this.selectedIds = const {},
  });

  LibraryState copyWith({
    List<Book>? books,
    ImportPhase? importing,
    bool clearImporting = false,
    String? error,
    bool clearError = false,
    bool? selectionMode,
    Set<int>? selectedIds,
  }) {
    return LibraryState(
      books: books ?? this.books,
      importing: clearImporting ? null : (importing ?? this.importing),
      error: clearError ? null : (error ?? this.error),
      selectionMode: selectionMode ?? this.selectionMode,
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }
}

class LibraryNotifier extends AsyncNotifier<LibraryState> {
  final BookDao _bookDao = BookDao();
  final ImporterService _importer = ImporterService();

  @override
  Future<LibraryState> build() async {
    final books = await _bookDao.listAll();
    return LibraryState(books: books);
  }

  // 弹出系统选择器，导入用户选择的 txt / epub
  // 用 FileType.any 而不是 custom：
  //   - macOS 上 file_picker 把 allowedExtensions 转 UTType 应用到 NSOpenPanel
  //     某些情况下会过度收紧（如 epub 文件被置灰）；用 any 由 Dart 侧自行过滤更稳
  //   - 跨平台行为也更一致
  Future<void> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final unsupported = <String>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      if (!isSupportedBookFile(path)) {
        unsupported.add(f.name);
        continue;
      }
      if (!await isWithinSizeLimit(path)) {
        // txt 限 10MB，epub 限 50MB（含图片资源）
        state = AsyncData(
          (state.value ?? const LibraryState())
              .copyWith(error: '${f.name} 超过大小上限'),
        );
        continue;
      }
      await _importOne(path);
    }
    if (unsupported.isNotEmpty) {
      state = AsyncData((state.value ?? const LibraryState()).copyWith(
        error: '以下文件格式不支持（仅 txt / epub）：${unsupported.join('、')}',
      ));
    }
    await refresh();
  }

  Future<void> _importOne(String externalPath) async {
    state = AsyncData((state.value ?? const LibraryState())
        .copyWith(importing: ImportPhase.copying, clearError: true));
    try {
      await _importer.importFile(
        externalPath,
        onProgress: (phase) {
          state = AsyncData(
              (state.value ?? const LibraryState()).copyWith(importing: phase));
        },
      );
    } on ImportException catch (e) {
      state = AsyncData(
          (state.value ?? const LibraryState()).copyWith(error: e.message));
    } catch (e) {
      // 兜底：捕获任何未被 ImporterService 包装的异常，避免 UI 无反馈
      state = AsyncData(
          (state.value ?? const LibraryState()).copyWith(error: '导入失败：$e'));
    } finally {
      state = AsyncData((state.value ?? const LibraryState())
          .copyWith(clearImporting: true));
    }
  }

  // 刷新书架数据，但保留 error / 多选 / 导入进度 等 UI 状态
  // （旧版本会重建整个 LibraryState 把 error 一起清掉，导致导入失败"看上去没反应"）
  Future<void> refresh() async {
    final books = await _bookDao.listAll();
    final cur = state.value ?? const LibraryState();
    state = AsyncData(cur.copyWith(books: books));
  }

  Future<void> deleteBook(Book book) async {
    await _bookDao.delete(book.id);
    await BookStorage.deleteFile(book.filePath);
    await refresh();
  }

  // 进入多选模式，并预选第一本（通常是长按触发的那本）
  void enterSelection(int firstId) {
    final cur = state.value ?? const LibraryState();
    state = AsyncData(cur.copyWith(
      selectionMode: true,
      selectedIds: {firstId},
    ));
  }

  // 切换某本书的选中状态；若全部取消则自动退出多选模式
  void toggleSelect(int id) {
    final cur = state.value ?? const LibraryState();
    if (!cur.selectionMode) return;
    final next = Set<int>.from(cur.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    if (next.isEmpty) {
      state = AsyncData(cur.copyWith(
        selectionMode: false,
        selectedIds: const {},
      ));
    } else {
      state = AsyncData(cur.copyWith(selectedIds: next));
    }
  }

  // 全选当前书架所有书
  void selectAll() {
    final cur = state.value ?? const LibraryState();
    if (cur.books.isEmpty) return;
    state = AsyncData(cur.copyWith(
      selectionMode: true,
      selectedIds: cur.books.map((b) => b.id).toSet(),
    ));
  }

  // 退出多选模式，清空选择
  void exitSelection() {
    final cur = state.value ?? const LibraryState();
    if (!cur.selectionMode) return;
    state = AsyncData(cur.copyWith(
      selectionMode: false,
      selectedIds: const {},
    ));
  }

  // 批量删除选中书籍：循环调用单本删除，结束后统一 refresh
  // 单本失败不阻断其他，错误信息合并展示
  Future<void> deleteSelected() async {
    final cur = state.value ?? const LibraryState();
    if (cur.selectedIds.isEmpty) return;
    final targets = cur.books.where((b) => cur.selectedIds.contains(b.id)).toList();
    final failures = <String>[];
    for (final b in targets) {
      try {
        await _bookDao.delete(b.id);
        await BookStorage.deleteFile(b.filePath);
      } catch (e) {
        failures.add('${b.title}: $e');
      }
    }
    final books = await _bookDao.listAll();
    state = AsyncData(LibraryState(
      books: books,
      error: failures.isEmpty ? null : '部分删除失败：\n${failures.join('\n')}',
    ));
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);
