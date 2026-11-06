// 全文搜索服务：查询 FTS 元数据并从正式书籍文件生成摘要和跳转位置。
import '../../core/db/daos.dart';
import '../../core/db/text_index.dart';
import '../../core/storage/book_storage.dart';

typedef SearchCancellationCheck = bool Function();

const int kDefaultSearchResultLimit = 100;

class SearchResultSet {
  final List<SearchHit> hits;
  final bool truncated;
  final List<SearchReadIssue> issues;

  const SearchResultSet({
    required this.hits,
    this.truncated = false,
    this.issues = const [],
  });

  bool get isIncomplete => issues.isNotEmpty;

  static const empty = SearchResultSet(hits: []);
}

// 单章读取失败随结果返回，既保留正常命中，也不把部分成功伪装成完整搜索。
class SearchReadIssue {
  final int bookId;
  final int chapterId;
  final Object error;
  final StackTrace stackTrace;

  const SearchReadIssue({
    required this.bookId,
    required this.chapterId,
    required this.error,
    required this.stackTrace,
  });
}

class SearchService {
  SearchService({
    SearchDao? dao,
    BookStorage? storage,
    this.resultLimit = kDefaultSearchResultLimit,
  }) : _dao = dao ?? SearchDao(),
       _storage = storage ?? BookStorage.shared,
       assert(resultLimit > 0);

  final SearchDao _dao;
  final BookStorage _storage;
  final int resultLimit;
  Future<SearchResultSet> _searchQueue = Future.value(SearchResultSet.empty);

  // 把用户输入转成 FTS5 安全查询，从 DAO 拿全库命中章节，再流式扫描
  // 章节原文生成每一个出现位置。队列确保旧请求释放文件后再开始新请求。
  Future<SearchResultSet> search(
    String raw, {
    SearchCancellationCheck? isCancelled,
  }) async {
    final next = _searchQueue.then(
      (_) => _searchNow(raw, isCancelled: isCancelled),
    );
    _searchQueue = next.catchError((_) => SearchResultSet.empty);
    return next;
  }

  Future<SearchResultSet> _searchNow(
    String raw, {
    SearchCancellationCheck? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return SearchResultSet.empty;

    final ftsQuery = toBigramQuery(raw);
    if (ftsQuery.isEmpty) return SearchResultSet.empty;
    // 多取一个候选章节，用来判断是否已经触及展示上限。
    final matches = await _dao.queryMatches(ftsQuery, limit: resultLimit + 1);
    if (isCancelled?.call() ?? false) return SearchResultSet.empty;
    if (matches.isEmpty) return SearchResultSet.empty;

    final hits = <SearchHit>[];
    final issues = <SearchReadIssue>[];
    for (final match in matches) {
      if (isCancelled?.call() ?? false) return SearchResultSet.empty;
      _ChapterSearchResult? chapterResult;
      try {
        chapterResult = await _readExcerpts(
          match,
          raw,
          maxHits: resultLimit + 1 - hits.length,
          isCancelled: isCancelled,
        );
      } catch (error, stackTrace) {
        if (isCancelled?.call() ?? false) return SearchResultSet.empty;
        issues.add(
          SearchReadIssue(
            bookId: match.bookId,
            chapterId: match.chapterId,
            error: error,
            stackTrace: stackTrace,
          ),
        );
        continue;
      }
      if (chapterResult == null) return SearchResultSet.empty;
      for (final excerpt in chapterResult.excerpts) {
        hits.add(
          SearchHit(
            bookId: match.bookId,
            bookTitle: match.bookTitle,
            chapterId: match.chapterId,
            chapterIndex: match.chapterIndex,
            chapterTitle: match.chapterTitle,
            snippet: excerpt.snippet,
            charOffset: excerpt.charOffset,
            matchLength: excerpt.matchLength,
          ),
        );
      }
      if (hits.length > resultLimit || chapterResult.hasMore) {
        return SearchResultSet(
          hits: hits.take(resultLimit).toList(growable: false),
          truncated: true,
          issues: List.unmodifiable(issues),
        );
      }
    }

    // resultLimit + 1 个候选章节说明数据库侧也触及上限。正常的
    // bigram 命中都会产生至少一个精确位置，因此应提示仍有候选未展示。
    final candidateLimitReached = matches.length > resultLimit;
    return SearchResultSet(
      hits: hits.take(resultLimit).toList(growable: false),
      truncated: candidateLimitReached || hits.length > resultLimit,
      issues: List.unmodifiable(issues),
    );
  }

  // 按 UTF-8 小块扫描，滚动缓冲区只保留前文上下文、最长查询词和当前块。
  // 这样可以返回同章多个命中，同时避免把长章节整段载入内存。
  Future<_ChapterSearchResult?> _readExcerpts(
    ChapterMatchRow match,
    String rawQuery, {
    required int maxHits,
    SearchCancellationCheck? isCancelled,
  }) async {
    const contextChars = 24;
    const fallbackChars = contextChars * 2;
    final retainChars = contextChars + _maxSearchTermLength(rawQuery) + 1;
    var buffer = '';
    var head = '';
    var bufferStartChar = 0;
    var searchFrom = 0;
    final excerpts = <_SearchExcerpt>[];

    await for (final chunk in _storage.readUtf8RangeChunks(
      match.bookFilePath,
      startByte: match.chapterStartByte,
      endByte: match.chapterEndByte,
    )) {
      if (isCancelled?.call() ?? false) return null;
      if (head.length <= fallbackChars) {
        final candidate = head + chunk;
        final headEnd = _safePrefixEnd(
          candidate,
          (fallbackChars + 1).clamp(0, candidate.length),
        );
        head = candidate.substring(0, headEnd);
      }
      buffer += chunk;
      while (true) {
        final found = findNextTextMatch(
          buffer,
          rawQuery,
          startOffset: searchFrom,
        );
        if (found == null) {
          final drop = _safePrefixEnd(
            buffer,
            (buffer.length - retainChars).clamp(0, buffer.length),
          );
          if (drop > 0) {
            buffer = buffer.substring(drop);
            bufferStartChar += drop;
            searchFrom = (searchFrom - drop).clamp(0, buffer.length);
          }
          break;
        }

        // 等到当前块包含足够后文再生成摘要；文件结束时会统一处理尾部命中。
        if (buffer.length - found.endOffset < contextChars) {
          searchFrom = found.offset;
          break;
        }

        excerpts.add(
          _excerptForMatch(buffer, bufferStartChar, rawQuery, found),
        );
        if (excerpts.length >= maxHits) {
          return _ChapterSearchResult(excerpts: excerpts, hasMore: true);
        }
        searchFrom = found.endOffset;
        final drop = _safePrefixEnd(
          buffer,
          (searchFrom - contextChars).clamp(0, buffer.length),
        );
        if (drop > 0) {
          buffer = buffer.substring(drop);
          bufferStartChar += drop;
          searchFrom -= drop;
        }
      }
    }

    // 文件结束后不再等待后文，把缓冲区中剩余命中全部发布。
    while (true) {
      if (isCancelled?.call() ?? false) return null;
      final found = findNextTextMatch(
        buffer,
        rawQuery,
        startOffset: searchFrom,
      );
      if (found == null) break;
      excerpts.add(_excerptForMatch(buffer, bufferStartChar, rawQuery, found));
      if (excerpts.length >= maxHits) {
        final hasAnother =
            findNextTextMatch(buffer, rawQuery, startOffset: found.endOffset) !=
            null;
        return _ChapterSearchResult(excerpts: excerpts, hasMore: hasAnother);
      }
      searchFrom = found.endOffset;
    }

    // FTS 同时索引章节标题和正文；标题命中或 unicode61 归一化命中时，
    // 正文可能没有可定位的字面文本。保留该候选并跳到章节开头。
    if (excerpts.isEmpty) {
      return _ChapterSearchResult(
        excerpts: [
          _SearchExcerpt(
            snippet: makeSnippet(head, '', contextChars: contextChars),
            charOffset: 0,
            matchLength: 0,
          ),
        ],
      );
    }

    return _ChapterSearchResult(excerpts: excerpts);
  }

  _SearchExcerpt _excerptForMatch(
    String buffer,
    int bufferStartChar,
    String rawQuery,
    TextMatch match,
  ) {
    return _SearchExcerpt(
      snippet: makeSnippetForMatch(buffer, rawQuery, match),
      charOffset: bufferStartChar + match.offset,
      matchLength: match.length,
    );
  }

  int _maxSearchTermLength(String rawQuery) {
    var result = 2;
    for (final term in searchTerms(rawQuery)) {
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

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}

class _SearchExcerpt {
  final String snippet;
  final int charOffset;
  final int matchLength;

  const _SearchExcerpt({
    required this.snippet,
    required this.charOffset,
    required this.matchLength,
  });
}

class _ChapterSearchResult {
  final List<_SearchExcerpt> excerpts;
  final bool hasMore;

  const _ChapterSearchResult({required this.excerpts, this.hasMore = false});
}
