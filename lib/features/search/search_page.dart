// 搜索页：管理输入防抖、请求竞态保护与结果展示。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/app_tokens.dart';
import '../../shared/widgets/app_animated_switcher.dart';
import '../reader/reader_page.dart';
import '../recovery/application_data_recovery_notice.dart';
import 'search_service.dart';

typedef SearchRunner =
    Future<List<SearchHit>> Function(
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
  List<SearchHit> _hits = const [];
  bool _loading = false;
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

    if (text.trim().isEmpty) {
      setState(() {
        _hits = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // 非空查询使用防抖，避免每个字符都查一次数据库。
    _debounce = Timer(
      widget.debounceDuration,
      () => _runSearch(text, generation),
    );
  }

  bool _isCurrent(int generation) => mounted && generation == _searchGeneration;

  Future<void> _runSearch(String text, int generation) async {
    if (!_isCurrent(generation)) return;

    try {
      final hits = await _search(
        text,
        isCancelled: () => !_isCurrent(generation),
      );
      // 只有最新世代能写入 UI，避免旧结果或旧错误覆盖新查询。
      if (!_isCurrent(generation)) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } catch (e) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _hits = const [];
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
          ),
          onChanged: _onChanged,
        ),
      ),
      body: Column(
        children: [
          const ApplicationDataRecoveryNotice(),
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
    if (_controller.text.isEmpty) {
      return Center(
        key: const ValueKey('search-empty'),
        child: Text(
          context.l10n.searchEmptyHint,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        key: const ValueKey('search-no-results'),
        child: Text(context.l10n.noSearchResults),
      );
    }
    return ListView.separated(
      key: ValueKey('search-results-${_hits.length}-${_controller.text}'),
      itemCount: _hits.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _HitTile(hit: _hits[i])
          .animate(delay: (i < 8 ? 24 * i : 0).ms)
          .fadeIn(duration: AppMotion.fast)
          .slideY(begin: 0.04, end: 0, duration: AppMotion.fast),
    );
  }
}

class _HitTile extends StatelessWidget {
  final SearchHit hit;
  const _HitTile({required this.hit});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        '${hit.bookTitle} · ${hit.chapterTitle}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _SnippetText(snippet: hit.snippet),
      onTap: () => Navigator.of(context).push(
        appRoute(
          (_) => ReaderPage(
            bookId: hit.bookId,
            initialChapterIndex: hit.chapterIndex,
            initialCharOffset: hit.charOffset,
          ),
        ),
      ),
    );
  }
}

// 渲染含 <mark>...</mark> 的片段：把标记内的部分高亮显示
class _SnippetText extends StatelessWidget {
  final String snippet;
  const _SnippetText({required this.snippet});

  // 高亮色按主题分别取值：单一固定色无法同时与浅色 / 深色正文拉开区分度
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
    for (final m in regex.allMatches(snippet)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: snippet.substring(lastEnd, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(1),
          style: TextStyle(color: highlightColor, fontWeight: FontWeight.bold),
        ),
      );
      lastEnd = m.end;
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
