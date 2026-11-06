// 搜索页：管理输入防抖、请求竞态保护、按书筛选与结果展示。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../core/db/text_index.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/app_tokens.dart';
import '../../shared/widgets/app_animated_switcher.dart';
import '../reader/reader_page.dart';
import '../reader/reader_search_context.dart';
import '../recovery/application_data_recovery_notice.dart';
import 'search_service.dart';

typedef SearchRunner =
    Future<SearchResultSet> Function(
      String raw, {
      SearchCancellationCheck? isCancelled,
    });

class SearchPage extends ConsumerStatefulWidget {
  final SearchRunner? search;
  final Duration debounceDuration;

  const SearchPage({
    super.key,
    this.search,
    this.debounceDuration = const Duration(milliseconds: 250),
  });

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  late final SearchRunner _search;
  Timer? _debounce;
  int _searchGeneration = 0;
  SearchResultSet _result = SearchResultSet.empty;
  String _resultQuery = '';
  int? _selectedBookId;
  bool _loading = false;
  bool _queryTooShort = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search = widget.search ?? SearchService().search;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchGeneration++;
    _controller.dispose();
    super.dispose();
  }

  // 每次输入变化立即递增世代，使已在执行的旧请求当场失效。
  void _onChanged(String text) {
    final generation = ++_searchGeneration;
    _debounce?.cancel();
    final empty = text.trim().isEmpty;
    final supported = !empty && isSupportedSearchQuery(text);

    if (empty || !supported) {
      setState(() {
        _result = SearchResultSet.empty;
        _resultQuery = '';
        _selectedBookId = null;
        _loading = false;
        _queryTooShort = !empty;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _queryTooShort = false;
      _error = null;
    });

    _debounce = Timer(
      widget.debounceDuration,
      () => _runSearch(text, generation),
    );
  }

  bool _isCurrent(int generation) => mounted && generation == _searchGeneration;

  Future<void> _runSearch(String text, int generation) async {
    if (!_isCurrent(generation)) return;

    try {
      final result = await _search(
        text,
        isCancelled: () => !_isCurrent(generation),
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _result = result;
        _resultQuery = text;
        _selectedBookId = null;
        _loading = false;
      });
    } catch (e) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _result = SearchResultSet.empty;
        _resultQuery = '';
        _selectedBookId = null;
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.l10n.searchHint,
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.l10n.commonClear,
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
        ),
      ),
      body: Column(
        children: [
          const ApplicationDataRecoveryNotice(),
          if (!_loading && _error == null && _result.isIncomplete)
            Material(
              key: const ValueKey('search-partial-warning'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.searchPartiallyUnavailable(
                          _result.issues.length,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _onChanged(_controller.text),
                      child: Text(context.l10n.commonRetry),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: AppAnimatedSwitcher(child: _buildBody())),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: ValueKey('search-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return Center(
        key: const ValueKey('search-error'),
        child: Text(context.l10n.searchFailed(_error!)),
      );
    }
    if (_controller.text.trim().isEmpty) {
      return Center(
        key: const ValueKey('search-empty'),
        child: Text(
          context.l10n.searchEmptyHint,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_queryTooShort) {
      return Center(
        key: const ValueKey('search-too-short'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            context.l10n.searchMinimumLength,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (_result.hits.isEmpty) {
      return Center(
        key: const ValueKey('search-no-results'),
        child: Text(context.l10n.noSearchResults),
      );
    }

    final facets = _bookFacets(_result.hits);
    final visibleHits = _selectedBookId == null
        ? _result.hits
        : _result.hits
              .where((hit) => hit.bookId == _selectedBookId)
              .toList(growable: false);
    return Column(
      key: ValueKey('search-results-${_result.hits.length}-$_resultQuery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResultSummary(
          visibleCount: visibleHits.length,
          loadedCount: _result.hits.length,
          filtered: _selectedBookId != null,
          truncated: _result.truncated,
        ),
        if (facets.length > 1)
          SingleChildScrollView(
            key: const ValueKey('search-book-filters'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                FilterChip(
                  label: Text(context.l10n.searchAllBooks(_result.hits.length)),
                  selected: _selectedBookId == null,
                  onSelected: (_) => setState(() => _selectedBookId = null),
                ),
                for (final facet in facets) ...[
                  const SizedBox(width: AppSpacing.sm),
                  FilterChip(
                    label: Text('${facet.title} (${facet.count})'),
                    selected: _selectedBookId == facet.bookId,
                    onSelected: (_) =>
                        setState(() => _selectedBookId = facet.bookId),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            key: ValueKey(
              'search-result-list-${visibleHits.length}-$_selectedBookId',
            ),
            itemCount: visibleHits.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) =>
                _HitTile(
                      hit: visibleHits[i],
                      onTap: () => _openHit(visibleHits[i]),
                    )
                    .animate(delay: (i < 8 ? 24 * i : 0).ms)
                    .fadeIn(duration: AppMotion.fast)
                    .slideY(begin: 0.04, end: 0, duration: AppMotion.fast),
          ),
        ),
      ],
    );
  }

  List<_BookFacet> _bookFacets(List<SearchHit> hits) {
    final counts = <int, _BookFacet>{};
    for (final hit in hits) {
      final current = counts[hit.bookId];
      counts[hit.bookId] = _BookFacet(
        bookId: hit.bookId,
        title: hit.bookTitle,
        count: (current?.count ?? 0) + 1,
      );
    }
    return counts.values.toList(growable: false);
  }

  void _openHit(SearchHit hit) {
    final bookHits =
        _result.hits
            .where((candidate) => candidate.bookId == hit.bookId)
            .toList()
          ..sort((a, b) {
            final chapterOrder = a.chapterIndex.compareTo(b.chapterIndex);
            if (chapterOrder != 0) return chapterOrder;
            return a.charOffset.compareTo(b.charOffset);
          });
    final selectedIndex = bookHits.indexWhere(
      (candidate) =>
          candidate.chapterIndex == hit.chapterIndex &&
          candidate.charOffset == hit.charOffset &&
          candidate.matchLength == hit.matchLength,
    );
    final searchContext = ReaderSearchContext(
      query: _resultQuery,
      targets: [
        for (final candidate in bookHits)
          ReaderSearchTarget(
            chapterIndex: candidate.chapterIndex,
            charOffset: candidate.charOffset,
            matchLength: candidate.matchLength,
          ),
      ],
      initialTargetIndex: selectedIndex < 0 ? 0 : selectedIndex,
    );
    Navigator.of(context).push(
      appRoute(
        (_) => ReaderPage(bookId: hit.bookId, searchContext: searchContext),
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  final int visibleCount;
  final int loadedCount;
  final bool filtered;
  final bool truncated;

  const _ResultSummary({
    required this.visibleCount,
    required this.loadedCount,
    required this.filtered,
    required this.truncated,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              filtered
                  ? context.l10n.searchFilteredResultCount(
                      visibleCount,
                      loadedCount,
                    )
                  : context.l10n.searchResultCount(loadedCount),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          if (truncated)
            Text(
              context.l10n.searchResultLimitReached(loadedCount),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _BookFacet {
  final int bookId;
  final String title;
  final int count;

  const _BookFacet({
    required this.bookId,
    required this.title,
    required this.count,
  });
}

class _HitTile extends StatelessWidget {
  final SearchHit hit;
  final VoidCallback onTap;

  const _HitTile({required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        '${hit.bookTitle} · ${hit.chapterTitle}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _SnippetText(snippet: hit.snippet),
      onTap: onTap,
    );
  }
}

// 渲染含 <mark>...</mark> 的片段：把标记内的部分高亮显示。
class _SnippetText extends StatelessWidget {
  final String snippet;

  const _SnippetText({required this.snippet});

  static const _highlightLight = Color(0xFF2F7D72);
  static const _highlightDark = Color(0xFF6FB8AD);

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'<mark>(.*?)</mark>');
    final highlightColor = Theme.of(context).brightness == Brightness.dark
        ? _highlightDark
        : _highlightLight;
    var lastEnd = 0;
    for (final match in regex.allMatches(snippet)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: snippet.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: TextStyle(color: highlightColor, fontWeight: FontWeight.bold),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < snippet.length) {
      spans.add(TextSpan(text: snippet.substring(lastEnd)));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
