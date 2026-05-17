import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/book.dart';
import '../../domain/bookmark.dart';
import '../../domain/chapter.dart';
import '../../domain/reading_progress.dart';
import '../parser/book_format.dart';
import 'database.dart';
import 'text_index.dart';

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
  // chapters 表存原文，chapters_fts 存 bigram 化的 token 序列（unicode61 按空格分词）
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
          'content': c.content,
        });
        // FTS5 行用同一个 rowid，便于 join；title/search 都做 bigram 化
        // 这样用户搜 "你好"（2 字）能命中标题或正文里的连续 "你好"
        await txn.insert('chapters_fts', {
          'rowid': id,
          'title': toBigramTokens(c.title),
          'search': toBigramTokens(c.content),
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
        .map((r) => BookmarkWithMeta(
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
            ))
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
    final id = await _db.insert(
      'bookmarks',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'char_offset': charOffset,
        'note': note,
        'created_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  // [ftsQuery] 已 bigram 化的 FTS5 MATCH 表达式
  // [rawQuery] 用户原始输入，用于在 Dart 侧从 chapters.content 生成 snippet
  // （FTS5 内部存的是 bigram 序列，自带 snippet() 出来的位置不映射到原文，所以自己做）
  Future<List<SearchHit>> search({
    required String ftsQuery,
    required String rawQuery,
  }) async {
    if (ftsQuery.trim().isEmpty) return const [];
    final rows = await _db.rawQuery(
      '''
      SELECT
        b.id AS book_id,
        b.title AS book_title,
        c.id AS chapter_id,
        c.chapter_index AS chapter_index,
        c.title AS chapter_title,
        c.content AS chapter_content
      FROM chapters_fts
      JOIN chapters c ON chapters_fts.rowid = c.id
      JOIN books b ON c.book_id = b.id
      WHERE chapters_fts MATCH ?
      ORDER BY rank
      LIMIT 100
      ''',
      [ftsQuery],
    );
    return rows
        .map((r) => SearchHit(
              bookId: r['book_id'] as int,
              bookTitle: r['book_title'] as String,
              chapterId: r['chapter_id'] as int,
              chapterIndex: r['chapter_index'] as int,
              chapterTitle: r['chapter_title'] as String,
              snippet: makeSnippet(r['chapter_content'] as String, rawQuery),
            ))
        .toList();
  }
}
