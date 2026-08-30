import 'package:flutter/foundation.dart';

@immutable
class ReaderSearchTarget {
  final int chapterIndex;
  final int charOffset;
  final int matchLength;

  const ReaderSearchTarget({
    required this.chapterIndex,
    required this.charOffset,
    required this.matchLength,
  });
}

// 从全局搜索进入阅读器时携带的轻量上下文。只保存当前书的结果，避免阅读器
// 与搜索页的展示模型耦合，也不会影响从书架或书签进入的普通阅读流程。
@immutable
class ReaderSearchContext {
  final String query;
  final List<ReaderSearchTarget> targets;
  final int initialTargetIndex;

  const ReaderSearchContext({
    required this.query,
    required this.targets,
    required this.initialTargetIndex,
  }) : assert(targets.length > 0),
       assert(initialTargetIndex >= 0),
       assert(initialTargetIndex < targets.length);
}
