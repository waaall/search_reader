import 'package:flutter/foundation.dart';

// 书签实体：精确到章节内字符偏移
// 唯一约束：(book_id, chapter_index, char_offset)，重复加书签会覆盖 note
@immutable
class Bookmark {
  final int id;
  final int bookId;
  final int chapterIndex;
  final int charOffset;
  final String? note;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.charOffset,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'char_offset': charOffset,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Bookmark.fromRow(Map<String, Object?> row) {
    return Bookmark(
      id: row['id'] as int,
      bookId: row['book_id'] as int,
      chapterIndex: row['chapter_index'] as int,
      charOffset: row['char_offset'] as int,
      note: row['note'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }
}
