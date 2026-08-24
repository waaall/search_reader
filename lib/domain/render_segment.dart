// 阅读渲染分片实体：仅作为内部按需加载单元，不参与目录、搜索和书签语义。
import 'package:flutter/foundation.dart';

@immutable
class RenderSegment {
  final int id;
  final int chapterId;
  final int segmentIndex;
  final int startChar;
  final int endChar;
  final int startByte;
  final int endByte;

  const RenderSegment({
    required this.id,
    required this.chapterId,
    required this.segmentIndex,
    required this.startChar,
    required this.endChar,
    required this.startByte,
    required this.endByte,
  });

  int get charCount => endChar - startChar;

  factory RenderSegment.fromRow(Map<String, Object?> row) {
    return RenderSegment(
      id: row['id']! as int,
      chapterId: row['chapter_id']! as int,
      segmentIndex: row['segment_index']! as int,
      startChar: row['start_char']! as int,
      endChar: row['end_char']! as int,
      startByte: row['start_byte']! as int,
      endByte: row['end_byte']! as int,
    );
  }
}
