// 数据访问层：封装书籍原子导入、查询、进度、书签与全文搜索操作。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/book.dart';
import '../../domain/bookmark.dart';
import '../../domain/chapter.dart';
import '../../domain/reading_progress.dart';
import '../parser/book_format.dart';
import 'database.dart';
import 'database_operations.dart';
import 'text_index.dart';

// 数据访问层：每个表一个 DAO 类
// 所有 DAO 共享同一个 Database 单例

class BookDao {
  BookDao({Database? database}) : _database = database;

  final Database? _database;
  Database get _db => _database ?? AppDatabase.instance.db;

  // 列出所有书籍，按最近阅读时间倒序（无阅读则按创建时间）
  Future<List<Book>> listAll() async {
    // import_jobs 存在表示文件尚未原子发布，不能把半成品暴露给书架。
    final rows = await _db.rawQuery('''
      SELECT b.*
      FROM books b
      WHERE NOT EXISTS (
        SELECT 1 FROM import_jobs job WHERE job.book_id = b.id
      )
      ORDER BY COALESCE(b.last_read_at, b.created_at) DESC
    ''');
    return rows.map(Book.fromRow).toList();
  }

  Future<Book?> findById(int id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT b.*
      FROM books b
      WHERE b.id = ?
        AND NOT EXISTS (
          SELECT 1 FROM import_jobs job WHERE job.book_id = b.id
        )
      ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return Book.fromRow(rows.first);
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
    await deleteBookRecords(_db, bookId);
  }
}

class BookImportDao {
  BookImportDao({Database? database}) : _database = database;

  final Database? _database;
  Database get _db => _database ?? AppDatabase.instance.db;

  // books、chapters、FTS 和恢复日志必须在同一事务内提交。
  Future<Book> createPendingImport({
    required String title,
    String? author,
    required String stagedPath,
    required String targetPath,
    required ParsedBook parsed,
  }) async {
    final now = DateTime.now();
    final id = await _db.transaction((txn) async {
      final bookId = await txn.insert('books', {
        'title': title,
        'author': author,
        'file_path': targetPath,
        'encoding': parsed.encoding,
        'total_chars': parsed.totalChars,
        'created_at': now.millisecondsSinceEpoch,
        'last_read_at': null,
      });

      for (var index = 0; index < parsed.chapters.length; index++) {
        final chapter = parsed.chapters[index];
        final chapterId = await txn.insert('chapters', {
          'book_id': bookId,
          'chapter_index': index,
          'title': chapter.title,
          'start_char': chapter.startChar,
          'end_char': chapter.endChar,
        });
        await txn.insert('chapters_fts', {
          'rowid': chapterId,
          'title': toBigramTokens(chapter.title),
          'search': toBigramTokens(chapter.content),
        });
      }

      await txn.insert('import_jobs', {
        'book_id': bookId,
        'staged_path': stagedPath,
        'target_path': targetPath,
        'state': 'ready_to_finalize',
        'created_at': now.millisecondsSinceEpoch,
      });
      return bookId;
    });

    return Book(
      id: id,
      title: title,
      author: author,
      filePath: targetPath,
      encoding: parsed.encoding,
      totalChars: parsed.totalChars,
      createdAt: now,
    );
  }

  Future<void> markImportComplete(int bookId) async {
    await _db.delete('import_jobs', where: 'book_id = ?', whereArgs: [bookId]);
  }

  Future<void> cancelPendingImport(int bookId) async {
    await deleteBookRecords(_db, bookId);
  }
}

class ChapterDao {
  Database get _db => AppDatabase.instance.db;

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

  // 一次查询得到整个书架的全书进度，避免按书逐条查询造成 N+1 开销。
  // 章节起点 + 章节内偏移就是当前阅读位置在原文中的全局字符坐标。
  Future<List<BookProgressSummary>> listBookSummaries() async {
    final rows = await _db.rawQuery('''
      SELECT
        b.id AS book_id,
        b.total_chars AS total_chars,
        c.start_char AS chapter_start,
        rp.char_offset AS char_offset
      FROM books b
      LEFT JOIN reading_progress rp ON rp.book_id = b.id
      LEFT JOIN chapters c
        ON c.book_id = rp.book_id AND c.chapter_index = rp.chapter_index
      WHERE NOT EXISTS (
        SELECT 1 FROM import_jobs job WHERE job.book_id = b.id
      )
    ''');

    return rows.map((row) {
      final totalChars = row['total_chars'] as int;
      final chapterStart = (row['chapter_start'] as int?) ?? 0;
      final charOffset = (row['char_offset'] as int?) ?? 0;
      return BookProgressSummary(
        bookId: row['book_id'] as int,
        currentChar: (chapterStart + charOffset).clamp(0, totalChars),
        totalChars: totalChars,
      );
    }).toList();
  }
}

// 跨书书签视图：bookmark + 书名 + 章节标题（用于全局书签页面展示）
class BookmarkWithMeta {
  final Bookmark bookmark;
  final String bookTitle;
  final String chapterTitle;

  const BookmarkWithMeta({
    required this.bookmark,
    required this.bookTitle,
    required this.chapterTitle,
  });
}

class BookmarkDao {
  Database get _db => AppDatabase.instance.db;

  // 列出全部书签：按书分组（书名升序），同书内按章节 + 章节内位置升序
  // chapter_title 用 LEFT JOIN 兜底（理论上 chapters 不会缺，但 LEFT JOIN 更鲁棒）
  Future<List<BookmarkWithMeta>> listAll() async {
    final rows = await _db.rawQuery('''
      SELECT
        bm.id, bm.book_id, bm.chapter_index, bm.char_offset, bm.note, bm.created_at,
        b.title AS book_title,
        c.title AS chapter_title
      FROM bookmarks bm
      JOIN books b ON b.id = bm.book_id
      LEFT JOIN chapters c
        ON c.book_id = bm.book_id AND c.chapter_index = bm.chapter_index
      ORDER BY b.title ASC, bm.chapter_index ASC, bm.char_offset ASC
    ''');
    return rows
        .map(
          (r) => BookmarkWithMeta(
            bookmark: Bookmark.fromRow({
              'id': r['id'],
              'book_id': r['book_id'],
              'chapter_index': r['chapter_index'],
              'char_offset': r['char_offset'],
              'note': r['note'],
              'created_at': r['created_at'],
            }),
            bookTitle: r['book_title'] as String,
            // 章节缺失时返回空串，具体兜底文案交给 UI 按当前语言生成。
            chapterTitle: (r['chapter_title'] as String?) ?? '',
          ),
        )
        .toList();
  }

  // 列出某本书的所有书签：按章节顺序、章节内位置升序
  // 排序按位置而不是创建时间：用户在书签列表里看到的顺序与阅读顺序一致
  Future<List<Bookmark>> listByBook(int bookId) async {
    final rows = await _db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index ASC, char_offset ASC',
    );
    return rows.map(Bookmark.fromRow).toList();
  }

  // upsert：(book_id, chapter_index, char_offset) 已存在则覆盖 note 与 created_at
  // 通过唯一索引 + ConflictAlgorithm.replace 实现，原子操作
  // 返回插入/更新后的 Bookmark（带新 id）
  Future<Bookmark> upsert({
    required int bookId,
    required int chapterIndex,
    required int charOffset,
    String? note,
  }) async {
    final now = DateTime.now();
    final id = await _db.insert('bookmarks', {
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'char_offset': charOffset,
      'note': note,
      'created_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return Bookmark(
      id: id,
      bookId: bookId,
      chapterIndex: chapterIndex,
      charOffset: charOffset,
      note: note,
      createdAt: now,
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // 阅读器右上角图标判断：当前章节内 [start, end) 区间是否有书签
  // end 不含，等同 char_offset < end
  Future<List<Bookmark>> findInChapterRange({
    required int bookId,
    required int chapterIndex,
    required int startOffset,
    required int endOffset,
  }) async {
    final rows = await _db.query(
      'bookmarks',
      where:
          'book_id = ? AND chapter_index = ? AND char_offset >= ? AND char_offset < ?',
      whereArgs: [bookId, chapterIndex, startOffset, endOffset],
    );
    return rows.map(Bookmark.fromRow).toList();
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
    await _db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
  final int charOffset; // 命中关键词在章节内的字符偏移，用于跳转定位

  const SearchHit({
    required this.bookId,
    required this.bookTitle,
    required this.chapterId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.charOffset,
  });
}

// 搜索命中的原始行：DAO 只返回元信息 + 起止位置 + 文件路径，
// snippet 与命中字符偏移由 SearchService 用沙盒文件切片在 Dart 侧生成
class ChapterMatchRow {
  final int bookId;
  final String bookTitle;
  final String bookFilePath;
  final int chapterId;
  final int chapterIndex;
  final String chapterTitle;
  final int chapterStart;
  final int chapterEnd;

  const ChapterMatchRow({
    required this.bookId,
    required this.bookTitle,
    required this.bookFilePath,
    required this.chapterId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.chapterStart,
    required this.chapterEnd,
  });
}

class SearchDao {
  Database get _db => AppDatabase.instance.db;

  // 跨书全文搜索：返回命中行的元信息 + 起止位置 + 文件路径，最多 100 条
  // [ftsQuery] 已 bigram 化的 FTS5 MATCH 表达式
  // 沙盒文件读取与 snippet 生成交给 SearchService，DAO 层不做文件 I/O
  Future<List<ChapterMatchRow>> queryMatches(String ftsQuery) async {
    if (ftsQuery.trim().isEmpty) return const [];
    final rows = await _db.rawQuery(
      '''
      SELECT
        b.id AS book_id,
        b.title AS book_title,
        b.file_path AS book_file_path,
        c.id AS chapter_id,
        c.chapter_index AS chapter_index,
        c.title AS chapter_title,
        c.start_char AS chapter_start,
        c.end_char AS chapter_end
      FROM chapters_fts
      JOIN chapters c ON chapters_fts.rowid = c.id
      JOIN books b ON c.book_id = b.id
      WHERE chapters_fts MATCH ?
        AND NOT EXISTS (
          SELECT 1 FROM import_jobs job WHERE job.book_id = b.id
        )
      ORDER BY rank
      LIMIT 100
      ''',
      [ftsQuery],
    );
    return rows
        .map(
          (r) => ChapterMatchRow(
            bookId: r['book_id'] as int,
            bookTitle: r['book_title'] as String,
            bookFilePath: r['book_file_path'] as String,
            chapterId: r['chapter_id'] as int,
            chapterIndex: r['chapter_index'] as int,
            chapterTitle: r['chapter_title'] as String,
            chapterStart: r['chapter_start'] as int,
            chapterEnd: r['chapter_end'] as int,
          ),
        )
        .toList();
  }
}
