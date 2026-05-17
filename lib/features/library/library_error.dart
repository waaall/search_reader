import '../importer/import_progress.dart';

// 书架页可展示的错误数据：只保存结构化信息，具体语言由 UI 层本地化。
sealed class LibraryError {
  const LibraryError();
}

final class FileTooLargeError extends LibraryError {
  final String fileName;
  const FileTooLargeError(this.fileName);
}

final class UnsupportedFilesError extends LibraryError {
  final List<String> fileNames;
  const UnsupportedFilesError(this.fileNames);
}

final class ImportFailedError extends LibraryError {
  final ImportException exception;
  const ImportFailedError(this.exception);
}

final class UnexpectedImportError extends LibraryError {
  final Object details;
  const UnexpectedImportError(this.details);
}

final class DeleteFailure {
  final String title;
  final Object details;

  const DeleteFailure({required this.title, required this.details});
}

final class PartialDeleteFailedError extends LibraryError {
  final List<DeleteFailure> failures;
  const PartialDeleteFailedError(this.failures);
}
