import '../../core/db/daos.dart';
import '../../core/db/text_index.dart';
import '../../core/storage/book_storage.dart';

class SearchService {
  final SearchDao _dao = SearchDao();

  // 把用户输入转成 FTS5 安全查询，从 DAO 拿命中行，
  // 再按 (book_file_path, start_char, end_char) 切沙盒文件得到章节原文，
  // 在 Dart 侧生成 snippet 与跳转字符偏移
  // - bigram 化保证 ≥2 字关键词命中（trigram 至少 3 字）
  // - 文件 I/O 在此层：同一本书的多个命中只读一次文件
  Future<List<SearchHit>> search(String raw) async {
    final ftsQuery = toBigramQuery(raw);
    if (ftsQuery.isEmpty) return const [];
    final matches = await _dao.queryMatches(ftsQuery);
    if (matches.isEmpty) return const [];

    // 同一本书多个命中只读一次文件（解码 + 换行归一化是开销大头）
    final fullTextCache = <int, String>{};
    final hits = <SearchHit>[];
    for (final m in matches) {
      final full = fullTextCache[m.bookId] ??=
          await BookStorage.readFullText(m.bookFilePath);
      final start = m.chapterStart.clamp(0, full.length);
      final end = m.chapterEnd.clamp(0, full.length);
      final content = full.substring(start, end);
      hits.add(SearchHit(
        bookId: m.bookId,
        bookTitle: m.bookTitle,
        chapterId: m.chapterId,
        chapterIndex: m.chapterIndex,
        chapterTitle: m.chapterTitle,
        snippet: makeSnippet(content, raw),
        charOffset: findMatchOffset(content, raw),
      ));
    }
    return hits;
  }
}
