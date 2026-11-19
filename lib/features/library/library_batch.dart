// 书架批次只记录逐项结果，不参与导入、索引或删除事务。
enum LibraryBatchKind { importing, deleting }

enum LibraryItemOutcome { succeeded, skipped, failed }

class LibraryBatch {
  final LibraryBatchKind kind;
  final int total;
  final int succeeded;
  final int skipped;
  final int failed;

  const LibraryBatch(
    this.kind,
    this.total, {
    this.succeeded = 0,
    this.skipped = 0,
    this.failed = 0,
  });

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
