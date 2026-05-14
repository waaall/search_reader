import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../core/storage/book_storage.dart';
import '../../domain/book.dart';
import '../importer/import_progress.dart';
import '../importer/importer_service.dart';

// 书架状态：所有书 + 当前导入进度
class LibraryState {
  final List<Book> books;
  final ImportPhase? importing; // null 表示当前没有导入中
  final String? error;

  const LibraryState({
    this.books = const [],
    this.importing,
    this.error,
  });

  LibraryState copyWith({
    List<Book>? books,
    ImportPhase? importing,
    bool clearImporting = false,
    String? error,
    bool clearError = false,
  }) {
    return LibraryState(
      books: books ?? this.books,
      importing: clearImporting ? null : (importing ?? this.importing),
      error: clearError ? null : (error ?? this.error),
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

  // 弹出系统选择器，导入用户选择的 txt
  Future<void> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      if (!isSupportedBookFile(path)) continue;
      if (!await isWithinSizeLimit(path)) {
        state = AsyncData(
          (state.value ?? const LibraryState())
              .copyWith(error: '${f.name} 超过 10MB 上限'),
        );
        continue;
      }
      await _importOne(path);
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
    } finally {
      state = AsyncData((state.value ?? const LibraryState())
          .copyWith(clearImporting: true));
    }
  }

  Future<void> refresh() async {
    final books = await _bookDao.listAll();
    state = AsyncData(LibraryState(books: books));
  }

  Future<void> deleteBook(Book book) async {
    await _bookDao.delete(book.id);
    await BookStorage.deleteFile(book.filePath);
    await refresh();
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);
