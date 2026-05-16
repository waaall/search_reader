import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../shared/theme/app_tokens.dart';
import '../reader/reader_page.dart';
import 'search_service.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _service = SearchService();
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // 输入防抖，避免每个字符都查一次数据库
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _runSearch(text));
  }

  Future<void> _runSearch(String text) async {
    if (text.trim().isEmpty) {
      setState(() {
        _hits = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits = await _service.search(text);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
          decoration: const InputDecoration(
            hintText: '搜索全部书籍内容',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('搜索失败：$_error'));
    }
    if (_controller.text.isEmpty) {
      return const Center(
        child: Text(
          '输入关键词，跨书检索章节内容',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_hits.isEmpty) {
      return const Center(child: Text('没有匹配结果'));
    }
    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) =>
          _HitTile(hit: _hits[i]).animate().fadeIn(duration: AppMotion.fast),
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
        MaterialPageRoute(
          builder: (_) => ReaderPage(
            bookId: hit.bookId,
            initialChapterIndex: hit.chapterIndex,
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

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'<mark>(.*?)</mark>');
    var lastEnd = 0;
    for (final m in regex.allMatches(snippet)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: snippet.substring(lastEnd, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ));
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
