// 导入流程的阶段状态：UI 用来显示提示
enum ImportPhase {
  copying('正在复制文件'),
  parsing('正在解析章节'),
  indexing('正在建立索引'),
  done('导入完成');

  final String label;
  const ImportPhase(this.label);
}

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
  final String message;
  ImportException(this.message);
  @override
  String toString() => 'ImportException: $message';
}
