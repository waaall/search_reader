// 书架状态管理：负责导入、刷新、单本删除与批量删除交互。
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/application_data_recovery_provider.dart';
import '../../core/db/daos.dart';
import '../../domain/book.dart';
import '../../domain/reading_progress.dart';
import '../importer/import_progress.dart';
import '../importer/importer_service.dart';
import 'book_deletion_service.dart';
import 'library_error.dart';
import 'library_batch.dart';

// 书架状态：所有书 + 当前导入进度 + 多选状态
class LibraryState {
  final List<Book> books;
  final Map<int, BookProgressSummary> progressByBookId;
  final ImportPhase? importing; // null 表示当前没有导入中
  final LibraryBatch? batch;
  final String currentName;
  final bool busy;
  final bool refreshFailed;
  final LibraryError? error;
  final bool selectionMode; // 是否处于多选模式
  final Set<int> selectedIds; // 已选中的书籍 id
  final List<String> decodingWarningTitles;

  const LibraryState({
    this.books = const [],
    this.progressByBookId = const {},
    this.importing,
    this.batch,
    this.currentName = '',
    this.busy = false,
    this.refreshFailed = false,
    this.error,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.decodingWarningTitles = const [],
  });

  LibraryState copyWith({
    List<Book>? books,
    Map<int, BookProgressSummary>? progressByBookId,
    LibraryBatch? batch,
    bool clearBatch = false,
    String? currentName,
    bool? busy,
    bool? refreshFailed,
    ImportPhase? importing,
    bool clearImporting = false,
    LibraryError? error,
    bool clearError = false,
    bool? selectionMode,
    Set<int>? selectedIds,
    List<String>? decodingWarningTitles,
  }) {
    return LibraryState(
      batch: clearBatch ? null : (batch ?? this.batch),
      currentName: currentName ?? this.currentName,
      busy: busy ?? this.busy,
      refreshFailed: refreshFailed ?? this.refreshFailed,
      books: books ?? this.books,
      progressByBookId: progressByBookId ?? this.progressByBookId,
      importing: clearImporting ? null : (importing ?? this.importing),
      error: clearError ? null : (error ?? this.error),
      selectionMode: selectionMode ?? this.selectionMode,
      selectedIds: selectedIds ?? this.selectedIds,
      decodingWarningTitles:
          decodingWarningTitles ?? this.decodingWarningTitles,
    );
  }
}

class LibraryNotifier extends AsyncNotifier<LibraryState> {
  final BookDao _bookDao = BookDao();
  final ProgressDao _progressDao = ProgressDao();
  final ImporterService _importer = ImporterService();
  final BookDeletionService _deletionService = BookDeletionService();

  // UI 禁用只是第一道防线，业务入口也要拒绝恢复期间的变更操作。
  bool get _recoveryRunning =>
      ref.read(applicationDataRecoveryProvider).isRunning;

  @override
  Future<LibraryState> build() async {
    final data = await _loadLibraryData();
    return LibraryState(
      books: data.books,
      progressByBookId: data.progressByBookId,
    );
  }

  // 书籍与进度始终成组刷新，保证书架标题、时间和百分比来自同一轮数据。
  Future<({List<Book> books, Map<int, BookProgressSummary> progressByBookId})>
  _loadLibraryData() async {
    final books = await _bookDao.listAll();
    final summaries = await _progressDao.listBookSummaries();
    return (
      books: books,
      progressByBookId: {
        for (final summary in summaries) summary.bookId: summary,
      },
    );
  }

  // 弹出系统选择器，导入用户选择的 txt / epub
  // 用 FileType.any 而不是 custom：
  //   - macOS 上 file_picker 把 allowedExtensions 转 UTType 应用到 NSOpenPanel
  //     某些情况下会过度收紧（如 epub 文件被置灰）；用 any 由 Dart 侧自行过滤更稳
  //   - 跨平台行为也更一致
  Future<void> pickAndImport() async {
    if (!_beginOperation()) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty || _recoveryRunning) return;
      final issues = <LibraryError>[];
      await _runBatch(
        LibraryBatchKind.importing,
        result.files,
        (file) => file.name,
        (file) async {
          final (outcome, issue) = await _importItem(file);
          if (issue != null) issues.add(issue);
          return outcome;
        },
      );
      if (issues.isNotEmpty) {
        state = AsyncData(
          _current.copyWith(batch: _current.batch!.withImportIssues(issues)),
        );
      }
      await refresh();
    } catch (e) {
      _setError(UnexpectedImportError(e));
    } finally {
      _endOperation();
    }
  }

  LibraryState get _current => state.requireValue;

  // 选择器打开前即占用入口，避免连续点击启动两轮操作。
  bool _beginOperation() {
    if (state.value == null || _current.busy || _recoveryRunning) return false;
    state = AsyncData(_current.copyWith(busy: true));
    return true;
  }

  void _endOperation() {
    state = AsyncData(
      _current.copyWith(busy: false, clearImporting: true, currentName: ''),
    );
  }

  void _setError(LibraryError error) {
    state = AsyncData(_current.copyWith(error: error));
  }

  // 批次只负责逐项计数；调用方先发布业务结果，再独立刷新书架。
  Future<void> _runBatch<T>(
    LibraryBatchKind kind,
    List<T> items,
    String Function(T) name,
    Future<LibraryItemOutcome> Function(T) handle,
  ) async {
    if (items.isEmpty) return;
    var progress = LibraryBatch(kind, items.length);
    state = AsyncData(_current.copyWith(batch: progress, clearError: true));
    for (final item in items) {
      state = AsyncData(
        _current.copyWith(currentName: name(item), clearImporting: true),
      );
      final outcome = await handle(item);
      progress = progress.record(outcome);
      state = AsyncData(_current.copyWith(batch: progress));
    }
  }

  // 每个输入只产生一个结果；单项异常不会吞掉此前的明细或中断后续文件。
  Future<(LibraryItemOutcome, LibraryError?)> _importItem(
    PlatformFile file,
  ) async {
    try {
      final path = file.path;
      if (path == null) {
        return (LibraryItemOutcome.failed, UnreadableFileError(file.name));
      }
      if (!isSupportedBookFile(path)) {
        return (LibraryItemOutcome.skipped, UnsupportedFilesError([file.name]));
      }
      if (!await isWithinSizeLimit(path)) {
        return (LibraryItemOutcome.skipped, FileTooLargeError(file.name));
      }
      final result = await _importer.importFile(
        path,
        onProgress: (phase) {
          state = AsyncData(
            (state.value ?? const LibraryState()).copyWith(importing: phase),
          );
        },
      );
      if (result.hadDecodingErrors) {
        // 批量导入时累积告警，后续成功或失败均不能抹掉此前的有损转换提示。
        final current = state.value ?? const LibraryState();
        state = AsyncData(
          current.copyWith(
            decodingWarningTitles: List.unmodifiable({
              ...current.decodingWarningTitles,
              result.title,
            }),
          ),
        );
      }
      return (LibraryItemOutcome.succeeded, null);
    } on ImportException catch (e) {
      return (LibraryItemOutcome.failed, ImportFailedError(file.name, e));
    } catch (e) {
      return (
        LibraryItemOutcome.failed,
        ImportFailedError(file.name, ImportException.unexpected(e)),
      );
    }
  }

  void dismissBatch() {
    if (!_current.busy) state = AsyncData(_current.copyWith(clearBatch: true));
  }

  Future<void> retryRefresh() async {
    if (_current.busy || _recoveryRunning) return;
    state = AsyncData(_current.copyWith(busy: true));
    try {
      await refresh();
    } finally {
      _endOperation();
    }
  }

  void dismissDecodingWarnings() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(decodingWarningTitles: const []));
  }

  int _refreshVersion = 0;

  // 刷新书架数据，但保留 error / 多选 / 导入进度 等 UI 状态
  // （旧版本会重建整个 LibraryState 把 error 一起清掉，导致导入失败"看上去没反应"）
  Future<void> refresh() async {
    final version = ++_refreshVersion;
    try {
      final data = await _loadLibraryData();
      if (version != _refreshVersion) return;
      state = AsyncData(
        _current.copyWith(
          books: data.books,
          progressByBookId: data.progressByBookId,
          refreshFailed: false,
        ),
      );
    } catch (_) {
      if (version != _refreshVersion) return;
      state = AsyncData(_current.copyWith(refreshFailed: true));
    }
  }

  // 只移除事务已提交的书，并使删除前启动的读取失效。
  void _removeCommitted(Set<int> ids) {
    if (ids.isEmpty) return;
    ++_refreshVersion;
    final cur = _current;
    final selected = cur.selectedIds.difference(ids);
    state = AsyncData(
      cur.copyWith(
        books: cur.books.where((b) => !ids.contains(b.id)).toList(),
        progressByBookId: Map.of(cur.progressByBookId)
          ..removeWhere((id, _) => ids.contains(id)),
        selectedIds: selected,
        selectionMode: cur.selectionMode && selected.isNotEmpty,
      ),
    );
  }

  Future<void> deleteBook(Book book) async {
    if (!_beginOperation()) return;
    try {
      state = AsyncData(_current.copyWith(clearBatch: true, clearError: true));
      await _deletionService.delete(book);
      _removeCommitted({book.id});
      await refresh();
    } catch (e) {
      _setError(
        PartialDeleteFailedError([
          DeleteFailure(title: book.title, details: e),
        ]),
      );
    } finally {
      _endOperation();
    }
  }

  // 进入多选模式，并预选第一本（通常是长按触发的那本）
  void enterSelection(int firstId) {
    final cur = state.value ?? const LibraryState();
    state = AsyncData(
      cur.copyWith(selectionMode: true, selectedIds: {firstId}),
    );
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
      state = AsyncData(
        cur.copyWith(selectionMode: false, selectedIds: const {}),
      );
    } else {
      state = AsyncData(cur.copyWith(selectedIds: next));
    }
  }

  // 全选当前书架所有书
  void selectAll() {
    final cur = state.value ?? const LibraryState();
    if (cur.books.isEmpty) return;
    state = AsyncData(
      cur.copyWith(
        selectionMode: true,
        selectedIds: cur.books.map((b) => b.id).toSet(),
      ),
    );
  }

  // 退出多选模式，清空选择
  void exitSelection() {
    final cur = state.value ?? const LibraryState();
    if (!cur.selectionMode) return;
    state = AsyncData(
      cur.copyWith(selectionMode: false, selectedIds: const {}),
    );
  }

  // 批量删除选中书籍：循环调用单本删除，结束后统一 refresh
  // 单本失败不阻断其他，错误信息合并展示
  Future<void> deleteSelected() async {
    final cur = state.value;
    if (cur == null) return;
    await _deleteTargets(
      cur.books.where((b) => cur.selectedIds.contains(b.id)).toList(),
    );
  }

  Future<void> _deleteTargets(List<Book> targets) async {
    if (targets.isEmpty || !_beginOperation()) return;
    final failures = <DeleteFailure>[];
    final committed = <int>{};
    try {
      await _runBatch(LibraryBatchKind.deleting, targets, (b) => b.title, (
        b,
      ) async {
        try {
          await _deletionService.delete(b);
          committed.add(b.id);
          return LibraryItemOutcome.succeeded;
        } catch (e) {
          failures.add(DeleteFailure(title: b.title, details: e));
          return LibraryItemOutcome.failed;
        }
      });
      _removeCommitted(committed);
      await refresh();
      state = AsyncData(
        _current.copyWith(
          selectionMode: false,
          selectedIds: const {},
          error: failures.isEmpty ? null : PartialDeleteFailedError(failures),
        ),
      );
    } finally {
      _endOperation();
    }
  }
}

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);
