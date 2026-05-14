import '../../core/db/daos.dart';
import '../../core/db/text_index.dart';

class SearchService {
  final SearchDao _dao = SearchDao();

  // 把用户输入转成 FTS5 安全查询，再交给 DAO
  // - bigram 化保证 ≥2 字关键词命中（trigram 至少 3 字）
  // - rawQuery 也透传给 DAO，用于 Dart 侧 snippet 高亮
  Future<List<SearchHit>> search(String raw) async {
    final ftsQuery = toBigramQuery(raw);
    if (ftsQuery.isEmpty) return const [];
    return _dao.search(ftsQuery: ftsQuery, rawQuery: raw);
  }
}
