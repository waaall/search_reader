import 'package:flutter/foundation.dart';

// 书籍实体：持久化在 books 表
@immutable
class Book {
  final int id;
  final String title;
  final String? author;
  final String filePath; // 沙盒内相对路径
  final String encoding; // 检测到的原始编码
  final int totalChars;
  final DateTime createdAt;
  final DateTime? lastReadAt;

  const Book({
    required this.id,
    required this.title,
    this.author,
    required this.filePath,
    required this.encoding,
    required this.totalChars,
    required this.createdAt,
    this.lastReadAt,
  });

  Book copyWith({
    String? title,
    String? author,
    DateTime? lastReadAt,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath,
      encoding: encoding,
      totalChars: totalChars,
      createdAt: createdAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'author': author,
        'file_path': filePath,
        'encoding': encoding,
        'total_chars': totalChars,
        'created_at': createdAt.millisecondsSinceEpoch,
        'last_read_at': lastReadAt?.millisecondsSinceEpoch,
      };

  factory Book.fromRow(Map<String, Object?> row) {
    return Book(
      id: row['id'] as int,
      title: row['title'] as String,
      author: row['author'] as String?,
      filePath: row['file_path'] as String,
      encoding: row['encoding'] as String,
      totalChars: row['total_chars'] as int,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      lastReadAt: row['last_read_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['last_read_at'] as int),
    );
  }
}
