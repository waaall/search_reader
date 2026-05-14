import 'package:flutter/foundation.dart';

// 章节实体：持久化在 chapters 表，正文不存这里（在 FTS5 索引或 txt 文件中）
@immutable
class Chapter {
  final int id;
  final int bookId;
  final int chapterIndex; // 0-based
  final String title;
  final int startChar; // 在原文中的起始字符位置（含）
  final int endChar; // 在原文中的结束字符位置（不含）

  const Chapter({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.title,
    required this.startChar,
    required this.endChar,
  });

  int get charCount => endChar - startChar;

  Map<String, Object?> toRow() => {
        'id': id,
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'title': title,
        'start_char': startChar,
        'end_char': endChar,
      };

  factory Chapter.fromRow(Map<String, Object?> row) {
    return Chapter(
      id: row['id'] as int,
      bookId: row['book_id'] as int,
      chapterIndex: row['chapter_index'] as int,
      title: row['title'] as String,
      startChar: row['start_char'] as int,
      endChar: row['end_char'] as int,
    );
  }
}
