// 全文搜索服务：查询 FTS 元数据并从正式书籍文件生成摘要和跳转位置。
import '../../core/db/daos.dart';
import '../../core/db/text_index.dart';
import '../../core/storage/book_storage.dart';

typedef SearchCancellationCheck = bool Function();

class SearchService {
  SearchService({SearchDao? dao, BookStorage? storage})
    : _dao = dao ?? SearchDao(),
      _storage = storage ?? BookStorage.shared;

  final SearchDao _dao;
  final BookStorage _storage;
  Future<List<SearchHit>> _searchQueue = Future.value(const []);

  // 把用户输入转成 FTS5 安全查询，从 DAO 拿全库命中行，
  // 再按章节的字符/字节范围切沙盒文件得到原文，
  // 在 Dart 侧生成 snippet 与跳转字符偏移
  // - bigram 化保证 ≥2 字关键词命中（trigram 至少 3 字）
  // - 文件 I/O 在此层：每次只读取一个命中章节，不缓存整本书
  Future<List<SearchHit>> search(
    String raw, {
    SearchCancellationCheck? isCancelled,
  }) async {
    // Riverpod 页面会在输入变化时发起新请求；队列确保旧请求释放文件和字符串后再开始新请求。
    final next = _searchQueue.then(
      (_) => _searchNow(raw, isCancelled: isCancelled),
    );
    _searchQueue = next.catchError((_) => const <SearchHit>[]);
    return next;
  }

  Future<List<SearchHit>> _searchNow(
    String raw, {
    SearchCancellationCheck? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return const [];

    final ftsQuery = toBigramQuery(raw);
    if (ftsQuery.isEmpty) return const [];
    final matches = await _dao.queryMatches(ftsQuery);
    if (isCancelled?.call() ?? false) return const [];
    if (matches.isEmpty) return const [];

    final hits = <SearchHit>[];
    for (final m in matches) {
      // 当前命中完成后再检查取消，避免旧查询继续读取后续章节。
      if (isCancelled?.call() ?? false) return const [];
      final excerpt = await _readExcerpt(m, raw, isCancelled: isCancelled);
      if (excerpt == null) return const [];
      if (isCancelled?.call() ?? false) return const [];
      hits.add(
        SearchHit(
          bookId: m.bookId,
          bookTitle: m.bookTitle,
          chapterId: m.chapterId,
          chapterIndex: m.chapterIndex,
          chapterTitle: m.chapterTitle,
          snippet: excerpt.snippet,
          charOffset: excerpt.charOffset,
        ),
      );
    }
    return hits;
  }

  // 所有书籍都按 UTF-8 小块扫描，找到命中后只保留上下文。
  Future<_SearchExcerpt?> _readExcerpt(
    ChapterMatchRow match,
    String rawQuery, {
    SearchCancellationCheck? isCancelled,
  }) async {
    const contextChars = 24;
    final retainChars = _maxSearchTermLength(rawQuery) > contextChars
        ? _maxSearchTermLength(rawQuery) + 1
        : contextChars + 1;
    var buffer = '';
    var bufferStartChar = 0;
    var head = '';
    TextMatch? found;

    await for (final chunk in _storage.readUtf8RangeChunks(
      match.bookFilePath,
      startByte: match.chapterStartByte,
      endByte: match.chapterEndByte,
    )) {
      if (isCancelled?.call() ?? false) return null;
      if (head.length < retainChars) {
        final nextHead = head + chunk;
        final headEnd = _safePrefixEnd(
          nextHead,
          retainChars.clamp(0, nextHead.length),
        );
        head = nextHead.substring(0, headEnd);
      }

      buffer += chunk;
      found ??= findTextMatch(buffer, rawQuery);
      if (found != null) {
        final current = found;
        if (buffer.length - current.offset >= current.length + contextChars) {
          break;
        }
        final drop = _safePrefixEnd(
          buffer,
          (current.offset - contextChars).clamp(0, buffer.length),
        );
        if (drop > 0) {
          buffer = buffer.substring(drop);
          bufferStartChar += drop;
          found = TextMatch(
            offset: current.offset - drop,
            length: current.length,
          );
        }
      } else if (buffer.length > retainChars) {
        final drop = _safePrefixEnd(buffer, buffer.length - retainChars);
        if (drop > 0) {
          buffer = buffer.substring(drop);
          bufferStartChar += drop;
        }
      }
    }

    final current = found;
    if (current == null) {
      final fallback = head.isNotEmpty ? head : buffer;
      return _SearchExcerpt(
        snippet: makeSnippet(fallback, rawQuery),
        charOffset: 0,
      );
    }

    final start = _safePrefixEnd(
      buffer,
      (current.offset - contextChars).clamp(0, buffer.length),
    );
    final rawEnd = (current.offset + current.length + contextChars).clamp(
      start,
      buffer.length,
    );
    final end = _safeSuffixEnd(buffer, rawEnd);
    final content = buffer.substring(start, end);
    return _SearchExcerpt(
      snippet: makeSnippet(content, rawQuery, contextChars: contextChars),
      charOffset: bufferStartChar + current.offset,
    );
  }

  int _maxSearchTermLength(String rawQuery) {
    var result = 2;
    for (final term in rawQuery.split(RegExp(r'\s+'))) {
      if (term.length > result) result = term.length;
    }
    return result;
  }

  int _safePrefixEnd(String text, int end) {
    if (end > 0 &&
        end < text.length &&
        _isHighSurrogate(text.codeUnitAt(end - 1)) &&
        _isLowSurrogate(text.codeUnitAt(end))) {
      return end - 1;
    }
    return end;
  }

  int _safeSuffixEnd(String text, int end) {
    if (end > 0 &&
        end < text.length &&
        _isHighSurrogate(text.codeUnitAt(end - 1)) &&
        _isLowSurrogate(text.codeUnitAt(end))) {
      return end + 1;
    }
    return end;
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}

class _SearchExcerpt {
  final String snippet;
  final int charOffset;

  const _SearchExcerpt({required this.snippet, required this.charOffset});
}
