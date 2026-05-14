import '../../core/db/daos.dart';

class SearchService {
  final SearchDao _dao = SearchDao();

  // 把用户输入转成 FTS5 安全查询
  // - 避免特殊字符引发语法错误
  // - 多关键词用 AND 连接
  String _sanitize(String raw) {
    final tokens = raw
        .replaceAll(RegExp(r'["\(\)\*]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"') // 用引号包住每个 token，避免 FTS5 把它当语法
        .toList();
    return tokens.join(' AND ');
  }

  Future<List<SearchHit>> search(String raw) async {
    final query = _sanitize(raw);
    if (query.isEmpty) return const [];
    return _dao.search(query);
  }
}
