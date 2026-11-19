// 书架批次只记录逐项结果，不参与导入、索引或删除事务。
import 'library_error.dart';

enum LibraryBatchKind { importing, deleting }

enum LibraryItemOutcome { succeeded, skipped, failed }

class LibraryBatch {
  final LibraryBatchKind kind;
  final int total;
  final int succeeded;
  final int skipped;
  final int failed;

  final List<LibraryError> importIssues;

  const LibraryBatch(
    this.kind,
    this.total, {
    this.succeeded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.importIssues = const [],
  });

  // 完成后一次性冻结明细，避免逐项复制长列表。
  LibraryBatch withImportIssues(List<LibraryError> issues) => LibraryBatch(
    kind,
    total,
    succeeded: succeeded,
    skipped: skipped,
    failed: failed,
    importIssues: List.unmodifiable(issues),
  );

  int get processed => succeeded + skipped + failed;

  // 处理数从结果推导，单本的阶段变化不会推进总进度。
  LibraryBatch record(LibraryItemOutcome outcome) => LibraryBatch(
    kind,
    total,
    succeeded: succeeded + (outcome == LibraryItemOutcome.succeeded ? 1 : 0),
    skipped: skipped + (outcome == LibraryItemOutcome.skipped ? 1 : 0),
    failed: failed + (outcome == LibraryItemOutcome.failed ? 1 : 0),
  );
}
