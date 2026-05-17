// 导入流程的阶段状态：UI 用来显示提示
enum ImportPhase { copying, parsing, indexing, done }

class ImportResult {
  final int bookId;
  final String title;
  final int chapterCount;
  final int totalChars;

  const ImportResult({
    required this.bookId,
    required this.title,
    required this.chapterCount,
    required this.totalChars,
  });
}

class ImportException implements Exception {
  final ImportFailureKind kind;
  final String? value;
  final Object? detail;

  const ImportException._({required this.kind, this.value, this.detail});

  const ImportException.unsupportedFormat(String extension)
    : this._(kind: ImportFailureKind.unsupportedFormat, value: extension);

  const ImportException.decodingFailed(Object detail)
    : this._(kind: ImportFailureKind.decodingFailed, detail: detail);

  const ImportException.unexpected(Object detail)
    : this._(kind: ImportFailureKind.unexpected, detail: detail);

  @override
  String toString() =>
      'ImportException(kind: $kind, value: $value, detail: $detail)';
}

// 导入失败分类：UI 层根据分类生成当前语言的人类可读提示。
enum ImportFailureKind { unsupportedFormat, decodingFailed, unexpected }
