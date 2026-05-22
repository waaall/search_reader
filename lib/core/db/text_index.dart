// 文本索引工具：bigram 分词与查询构造
//
// 背景：SQLite FTS5 内置 trigram 分词器要求查询 ≥3 字符；本项目改用
// "Dart 侧 bigram 化 + FTS5 unicode61" 的组合，让 ≥2 字符即可搜到。
//
// 索引侧：把章节正文切成连续 2 字符的 token 序列，用空格连接后存入
//   FTS5 的 search 列。FTS5 的 unicode61 分词器按空格切，每个 bigram
//   作为一个完整 token 存入倒排索引。
//
// 查询侧：把用户输入按同样规则切成 bigram，相邻 bigram 用 FTS5 的
//   phrase 紧邻语法（+）连接，确保命中的是连续子串而非分散匹配。
//
// 例：
//   原文 "你好世界" → 索引 token：[你好, 好世, 世界]
//   query "你好世" → "你好" + "好世"（紧邻短语）→ 等价于原文连续出现 "你好世"

const int _bigramSize = 2;

// 把文本切成 bigram 序列，用空格连接
// 输入会先做空白归一化（连续空白合并为一个空格），按空白分段后逐段 bigram 化
// 这样跨段落 / 跨标点的 bigram 不会出现，避免无意义命中
String toBigramTokens(String text) {
  if (text.isEmpty) return '';
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '';

  final out = StringBuffer();
  for (final segment in normalized.split(' ')) {
    if (segment.isEmpty) continue;
    if (segment.length < _bigramSize) {
      // 单字符段：作为 1-gram 入索引（少见，但避免漏字）
      if (out.isNotEmpty) out.write(' ');
      out.write(segment);
      continue;
    }
    for (var i = 0; i + _bigramSize <= segment.length; i++) {
      if (out.isNotEmpty) out.write(' ');
      out.write(segment.substring(i, i + _bigramSize));
    }
  }
  return out.toString();
}

// 构造 FTS5 MATCH 查询字符串
// 行为：
//   - 用户输入按空白分组（多关键词），每组内 bigram 化 + 紧邻短语
//   - 组之间用 AND 连接（多个关键词都要出现）
//   - 1 字符的组保留为单 token 查询（命中率取决于索引里是否有 1-gram）
//   - 空输入或全清洗后为空 → 返回空串，调用方应跳过查询
String toBigramQuery(String raw) {
  // 清掉 FTS5 特殊字符，避免语法错误（双引号 / 括号 / 通配符 / 减号）
  final cleaned = raw.replaceAll(RegExp(r'["\(\)\*\-\+]'), ' ');
  final groups = cleaned
      .split(RegExp(r'\s+'))
      .where((g) => g.isNotEmpty)
      .toList(growable: false);
  if (groups.isEmpty) return '';

  final groupExprs = <String>[];
  for (final g in groups) {
    final expr = _groupToPhrase(g);
    if (expr.isEmpty) continue;
    groupExprs.add(expr);
  }
  if (groupExprs.isEmpty) return '';
  if (groupExprs.length == 1) return groupExprs.first;
  return groupExprs.join(' AND ');
}

// 单组关键词 → 紧邻短语
//   "你好" → '"你好"'
//   "你好世" → '("你好" + "好世")'
//   "啊" → '"啊"'
String _groupToPhrase(String group) {
  if (group.isEmpty) return '';
  if (group.length < _bigramSize) return '"$group"';

  final bigrams = <String>[];
  for (var i = 0; i + _bigramSize <= group.length; i++) {
    bigrams.add('"${group.substring(i, i + _bigramSize)}"');
  }
  if (bigrams.length == 1) return bigrams.first;
  return '(${bigrams.join(' + ')})';
}

// 在原文中找命中位置，截取 ±[contextChars] 字符的上下文片段
// 返回值含 <mark>...</mark> 包住的关键词；查询为空或没找到时返回原文开头摘要
//
// 注意：这里只做一次匹配（首次出现位置），多个关键词时用最先匹配到的那个
// 已经能满足"快速定位是不是这条结果"的诉求；UI 不需要展示所有匹配
String makeSnippet(String content, String rawQuery, {int contextChars = 24}) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ');
  if (rawQuery.trim().isEmpty) {
    return _ellipsisHead(normalized, contextChars * 2);
  }
  // 多关键词时，优先用最长的那个找位置（更具体）
  final candidates = rawQuery
      .split(RegExp(r'\s+'))
      .where((g) => g.isNotEmpty)
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  for (final kw in candidates) {
    final idx = normalized.indexOf(kw);
    if (idx < 0) continue;
    return _buildHighlightedSegment(normalized, kw, idx, contextChars);
  }
  // 整个 query 都没在原文连续出现（FTS5 命中是按 bigram AND，可能误差），
  // 退化用第一个 bigram 找位置
  final firstKw = candidates.first;
  if (firstKw.length >= _bigramSize) {
    final bigram = firstKw.substring(0, _bigramSize);
    final idx = normalized.indexOf(bigram);
    if (idx >= 0) {
      return _buildHighlightedSegment(normalized, bigram, idx, contextChars);
    }
  }
  return _ellipsisHead(normalized, contextChars * 2);
}

String _buildHighlightedSegment(
    String normalized, String keyword, int idx, int ctx) {
  final start = (idx - ctx).clamp(0, normalized.length);
  final end = (idx + keyword.length + ctx).clamp(0, normalized.length);
  final prefix = start > 0 ? '...' : '';
  final suffix = end < normalized.length ? '...' : '';
  final segment = normalized.substring(start, end);
  // 高亮所有 keyword 出现位置（不仅仅首次），让用户一眼看到上下文密度
  final highlighted = segment.replaceAll(keyword, '<mark>$keyword</mark>');
  return '$prefix$highlighted$suffix';
}

String _ellipsisHead(String text, int len) {
  if (text.length <= len) return text;
  return '${text.substring(0, len)}...';
}

// 在原文中定位关键词，返回章节内字符偏移，供搜索结果跳转到命中位置
// 与 makeSnippet 不同：makeSnippet 在归一化文本上找位置只为展示片段，
// 这里必须用原文偏移——reader 的章节文本与字符偏移都基于原文（chapters.content）
// 多关键词时优先用最长的；都没找到时返回 0（落到章节开头）
int findMatchOffset(String content, String rawQuery) {
  if (rawQuery.trim().isEmpty) return 0;
  final candidates = rawQuery
      .split(RegExp(r'\s+'))
      .where((g) => g.isNotEmpty)
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (candidates.isEmpty) return 0;

  for (final kw in candidates) {
    final idx = content.indexOf(kw);
    if (idx >= 0) return idx;
  }
  // 整词未连续出现（FTS 按 bigram AND 命中可能有误差），退化用第一个 bigram 定位
  final firstKw = candidates.first;
  if (firstKw.length >= _bigramSize) {
    final idx = content.indexOf(firstKw.substring(0, _bigramSize));
    if (idx >= 0) return idx;
  }
  return 0;
}
