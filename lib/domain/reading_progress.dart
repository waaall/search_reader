import 'package:flutter/foundation.dart';

// 阅读进度：每本书一条
@immutable
class ReadingProgress {
  final int bookId;
  final int chapterIndex;
  final int charOffset; // 章节内字符偏移
  final DateTime updatedAt;

  const ReadingProgress({
    required this.bookId,
    required this.chapterIndex,
    required this.charOffset,
    required this.updatedAt,
  });

  Map<String, Object?> toRow() => {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'char_offset': charOffset,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ReadingProgress.fromRow(Map<String, Object?> row) {
    return ReadingProgress(
      bookId: row['book_id'] as int,
      chapterIndex: row['chapter_index'] as int,
      charOffset: row['char_offset'] as int,
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}

// 书架使用的整本书阅读进度摘要。
// 数据库仍保存“章节索引 + 章节内偏移”，这里统一换算为全书进度，避免 UI 重复计算。
@immutable
class BookProgressSummary {
  final int bookId;
  final int currentChar;
  final int totalChars;

  const BookProgressSummary({
    required this.bookId,
    required this.currentChar,
    required this.totalChars,
  });

  double get fraction {
    if (totalChars <= 0) return 0;
    return (currentChar / totalChars).clamp(0.0, 1.0);
  }
}
