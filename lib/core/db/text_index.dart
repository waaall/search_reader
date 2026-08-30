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

// 搜索页与正文定位共用的查询词清洗。必须与 [toBigramQuery] 使用同一套
// FTS 特殊字符规则，否则可能出现“索引命中、原文定位不到”的分歧。
List<String> searchTerms(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'["\(\)\*\-\+]'), ' ');
  final seen = <String>{};
  final terms = <String>[];
  for (final term in cleaned.split(RegExp(r'\s+'))) {
    if (term.isEmpty) continue;
    final key = term.toLowerCase();
    if (seen.add(key)) terms.add(term);
  }
  return terms;
}

// bigram 索引无法可靠支持普通正文里的单字符检索；UI 在发起查询前用此方法
// 给出明确提示，避免把“不支持”误呈现为“没有结果”。
bool isSupportedSearchQuery(String raw) {
  final terms = searchTerms(raw);
  return terms.isNotEmpty && terms.every((term) => term.length >= _bigramSize);
}

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
  final groups = searchTerms(raw);
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
String makeSnippet(String content, String rawQuery, {int contextChars = 24}) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ');
  if (rawQuery.trim().isEmpty) {
    return _ellipsisHead(normalized, contextChars * 2);
  }
  final match = findTextMatch(normalized, rawQuery);
  if (match != null) {
    return makeSnippetForMatch(
      normalized,
      rawQuery,
      match,
      contextChars: contextChars,
    );
  }
  return _ellipsisHead(normalized, contextChars * 2);
}

String makeSnippetForMatch(
  String content,
  String rawQuery,
  TextMatch match, {
  int contextChars = 24,
}) {
  final start = (match.offset - contextChars).clamp(0, content.length);
  final end = (match.endOffset + contextChars).clamp(0, content.length);
  final prefix = start > 0 ? '...' : '';
  final suffix = end < content.length ? '...' : '';
  final segment = content.substring(start, end);
  final highlighted = markSearchTerms(segment, rawQuery);
  return '$prefix$highlighted$suffix';
}

// 在原文片段中用 <mark> 标出所有查询词。匹配不区分大小写，但保留原文大小写。
String markSearchTerms(String text, String rawQuery) {
  final matches = findTextMatches(text, rawQuery);
  if (matches.isEmpty) return text;
  final out = StringBuffer();
  var cursor = 0;
  for (final match in matches) {
    if (match.offset > cursor) out.write(text.substring(cursor, match.offset));
    out
      ..write('<mark>')
      ..write(text.substring(match.offset, match.endOffset))
      ..write('</mark>');
    cursor = match.endOffset;
  }
  if (cursor < text.length) out.write(text.substring(cursor));
  return out.toString();
}

String _ellipsisHead(String text, int len) {
  if (text.length <= len) return text;
  return '${text.substring(0, len)}...';
}

class TextMatch {
  final int offset;
  final int length;

  const TextMatch({required this.offset, required this.length});

  int get endOffset => offset + length;
}

// 返回从 [startOffset] 开始的下一个命中。多个查询词同位置命中时保留最长词，
// 以免“李寻欢”被较短的“李寻”切碎。RegExp 的 caseSensitive=false 同时修复
// FTS unicode61 不区分英文大小写、Dart indexOf 却区分大小写造成的定位偏差。
TextMatch? findNextTextMatch(
  String content,
  String rawQuery, {
  int startOffset = 0,
}) {
  if (content.isEmpty) return null;
  final start = startOffset.clamp(0, content.length);
  TextMatch? best;
  for (final term in searchTerms(rawQuery)) {
    final matches = RegExp(
      RegExp.escape(term),
      caseSensitive: false,
      unicode: true,
    ).allMatches(content, start);
    final first = matches.isEmpty ? null : matches.first;
    if (first == null) continue;
    final candidate = TextMatch(
      offset: first.start,
      length: first.end - first.start,
    );
    if (best == null ||
        candidate.offset < best.offset ||
        (candidate.offset == best.offset && candidate.length > best.length)) {
      best = candidate;
    }
  }
  return best;
}

List<TextMatch> findTextMatches(
  String content,
  String rawQuery, {
  int? maxMatches,
}) {
  if (maxMatches != null && maxMatches <= 0) return const [];
  final matches = <TextMatch>[];
  var cursor = 0;
  while (cursor < content.length) {
    final match = findNextTextMatch(content, rawQuery, startOffset: cursor);
    if (match == null) break;
    matches.add(match);
    if (maxMatches != null && matches.length >= maxMatches) break;
    cursor = match.endOffset > cursor ? match.endOffset : cursor + 1;
  }
  return matches;
}

// 在原文中定位关键词，供摘要截取和阅读器跳转共用。
TextMatch? findTextMatch(String content, String rawQuery) {
  final exact = findNextTextMatch(content, rawQuery);
  if (exact != null) return exact;

  // 兼容历史行为：极少数按 bigram 命中但整词不连续的章节，退化到首个 bigram。
  final terms = searchTerms(rawQuery);
  if (terms.isEmpty || terms.first.length < _bigramSize) return null;
  return findNextTextMatch(content, terms.first.substring(0, _bigramSize));
}

// 保留原有 API：找不到时返回 0，兼容阅读跳转和已有调用方。
int findMatchOffset(String content, String rawQuery) {
  return findTextMatch(content, rawQuery)?.offset ?? 0;
}
