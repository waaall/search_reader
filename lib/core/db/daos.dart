import 'package:sqflite/sqflite.dart';

import '../../domain/book.dart';
import '../../domain/chapter.dart';
import '../../domain/reading_progress.dart';
import '../parser/book_format.dart';
import 'database.dart';

// 数据访问层：每个表一个 DAO 类
// 所有 DAO 共享同一个 Database 单例

class BookDao {
  Database get _db => AppDatabase.instance.db;

  // 列出所有书籍，按最近阅读时间倒序（无阅读则按创建时间）
  Future<List<Book>> listAll() async {
    final rows = await _db.query(
      'books',
      orderBy: 'COALESCE(last_read_at, created_at) DESC',
    );
    return rows.map(Book.fromRow).toList();
  }

  Future<Book?> findById(int id) async {
    final rows = await _db.query('books', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Book.fromRow(rows.first);
  }

  // 插入并返回带 id 的 Book
  Future<Book> insert({
    required String title,
    String? author,
    required String filePath,
    required String encoding,
    required int totalChars,
  }) async {
    final now = DateTime.now();
    final id = await _db.insert('books', {
      'title': title,
      'author': author,
      'file_path': filePath,
      'encoding': encoding,
      'total_chars': totalChars,
      'created_at': now.millisecondsSinceEpoch,
      'last_read_at': null,
    });
    return Book(
      id: id,
      title: title,
      author: author,
      filePath: filePath,
      encoding: encoding,
      totalChars: totalChars,
      createdAt: now,
    );
  }

  Future<void> updateLastRead(int bookId) async {
    await _db.update(
      'books',
      {'last_read_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  // 删除：级联清理章节与进度，FTS5 需手动清
  Future<void> delete(int bookId) async {
    await _db.transaction((txn) async {
      // 先拿到将被删除的 chapter ids，用于清理 FTS5
      final chapterRows = await txn.query(
        'chapters',
        columns: ['id'],
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      for (final row in chapterRows) {
        await txn.delete('chapters_fts',
            where: 'rowid = ?', whereArgs: [row['id']]);
      }
      await txn.delete('books', where: 'id = ?', whereArgs: [bookId]);
    });
  }
}

class ChapterDao {
  Database get _db => AppDatabase.instance.db;

  // 批量写入章节 + FTS5 索引（同事务，失败回滚）
  Future<void> insertAll(int bookId, List<ParsedChapter> chapters) async {
    await _db.transaction((txn) async {
      for (var i = 0; i < chapters.length; i++) {
        final c = chapters[i];
        final id = await txn.insert('chapters', {
          'book_id': bookId,
          'chapter_index': i,
          'title': c.title,
          'start_char': c.startChar,
          'end_char': c.endChar,
        });
        // FTS5 行用同一个 rowid，便于 join
        await txn.insert('chapters_fts', {
          'rowid': id,
          'title': c.title,
          'content': c.content,
        });
      }
    });
  }

  Future<List<Chapter>> listByBook(int bookId) async {
    final rows = await _db.query(
      'chapters',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index ASC',
    );
    return rows.map(Chapter.fromRow).toList();
  }

  Future<Chapter?> findByIndex(int bookId, int chapterIndex) async {
    final rows = await _db.query(
      'chapters',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
    );
    if (rows.isEmpty) return null;
    return Chapter.fromRow(rows.first);
  }
}

class ProgressDao {
  Database get _db => AppDatabase.instance.db;

  Future<ReadingProgress?> get(int bookId) async {
    final rows = await _db.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return null;
    return ReadingProgress.fromRow(rows.first);
  }

  // upsert 写入进度
  Future<void> save(ReadingProgress progress) async {
    await _db.insert(
      'reading_progress',
      progress.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class SettingsDao {
  Database get _db => AppDatabase.instance.db;

  Future<String?> get(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

// 全文搜索结果（跨章节 + 关联 books 信息）
class SearchHit {
  final int bookId;
  final String bookTitle;
  final int chapterId;
  final int chapterIndex;
  final String chapterTitle;
  final String snippet; // 含 <mark> 标记的上下文片段

  const SearchHit({
    required this.bookId,
    required this.bookTitle,
    required this.chapterId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.snippet,
  });
}

class SearchDao {
  Database get _db => AppDatabase.instance.db;

  // 跨书全文搜索：限制返回 100 条以避免 UI 卡顿
  Future<List<SearchHit>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final rows = await _db.rawQuery(
      '''
      SELECT
        b.id AS book_id,
        b.title AS book_title,
        c.id AS chapter_id,
        c.chapter_index AS chapter_index,
        c.title AS chapter_title,
        snippet(chapters_fts, 1, '<mark>', '</mark>', '...', 16) AS snippet
      FROM chapters_fts
      JOIN chapters c ON chapters_fts.rowid = c.id
      JOIN books b ON c.book_id = b.id
      WHERE chapters_fts MATCH ?
      ORDER BY rank
      LIMIT 100
      ''',
      [query],
    );
    return rows
        .map((r) => SearchHit(
              bookId: r['book_id'] as int,
              bookTitle: r['book_title'] as String,
              chapterId: r['chapter_id'] as int,
              chapterIndex: r['chapter_index'] as int,
              chapterTitle: r['chapter_title'] as String,
              snippet: r['snippet'] as String,
            ))
        .toList();
  }
}
