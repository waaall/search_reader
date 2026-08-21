// 应用数据操作协调器：串行化恢复、导入和删除，避免后台清理与文件发布互相踩踏。
import 'dart:async';

abstract final class ApplicationDataOperationCoordinator {
  static Future<void> _tail = Future<void>.value();

  // 恢复会扫描并清理 books/，必须与导入和删除共享同一条异步队列。
  static Future<T> run<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;

    await previous;
    try {
      return await operation();
    } finally {
      completed.complete();
    }
  }
}
