// 阅读页面：共用排版环境，按分片懒读取正文，并以实际字符布局保存和恢复位置。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/text_index.dart';
import '../../core/parser/render_segmenter.dart';
import '../../domain/reader_settings.dart';
import '../../domain/render_segment.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/theme/app_tokens.dart';
import '../settings/settings_provider.dart';
import 'bookmark_provider.dart';
import 'lazy_chapter_paginator.dart';
import 'reader_provider.dart';
import 'reader_search_context.dart';
import 'reader_text_layout.dart';
import 'reader_text_position.dart';
import 'segment_text_source.dart';
import 'widgets/reader_drawer.dart';
import 'widgets/reader_settings_sheet.dart';

class ReaderPage extends ConsumerWidget {
  final int bookId;
  // 可选：从搜索跳转时直接定位到指定章节与字符
  final int? initialChapterIndex;
  final int? initialCharOffset;
  final ReaderSearchContext? searchContext;

  const ReaderPage({
    super.key,
    required this.bookId,
    this.initialChapterIndex,
    this.initialCharOffset,
    this.searchContext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReader = ref.watch(readerProvider(bookId));
    final asyncSettings = ref.watch(readerSettingsProvider);

    return asyncReader.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(context.l10n.openBookFailed(e))),
      ),
      data: (state) => asyncSettings.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
          body: Center(child: Text(context.l10n.settingsLoadFailed(e))),
        ),
        data: (settings) => _ReaderShell(
          bookId: bookId,
          settings: settings,
          state: state,
          initialChapterIndex: initialChapterIndex,
          initialCharOffset: initialCharOffset,
          searchContext: searchContext,
        ),
      ),
    );
  }
}

class _ReaderShell extends ConsumerStatefulWidget {
  final int bookId;
  final ReaderState state;
  final ReaderSettings settings;
  final int? initialChapterIndex;
  final int? initialCharOffset;
  final ReaderSearchContext? searchContext;

  const _ReaderShell({
    required this.bookId,
    required this.state,
    required this.settings,
    this.initialChapterIndex,
    this.initialCharOffset,
    this.searchContext,
  });

  @override
  ConsumerState<_ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends ConsumerState<_ReaderShell> {
  bool _menuVisible = false;
  bool _didJumpToInitialChapter = false;
  bool _savingAndPopping = false;
  bool _allowPopAfterSave = false;
  late int _activeSearchTargetIndex;
  late bool _searchNavigationVisible;

  // 章节内最近上报的阅读偏移：翻页/滚动时更新（非响应式，不触发重建）。
  // 切换阅读模式、改字号等导致视图重建时用它保留当前位置；发生跳转后置空。
  int? _lastCharOffset;

  // 内边距：上下留出顶部菜单与页码空间
  static const _padding = EdgeInsets.fromLTRB(20, 48, 20, 32);

  @override
  void initState() {
    super.initState();
    final searchContext = widget.searchContext;
    _searchNavigationVisible = searchContext != null;
    _activeSearchTargetIndex = searchContext?.initialTargetIndex ?? 0;
    // 搜索上下文优先于旧的单点参数；书签等现有入口仍继续使用单点参数。
    final searchTarget = searchContext == null
        ? null
        : searchContext.targets[_activeSearchTargetIndex];
    final ic = searchTarget?.chapterIndex ?? widget.initialChapterIndex;
    final offset = searchTarget?.charOffset ?? widget.initialCharOffset ?? 0;
    if (ic != null && !_didJumpToInitialChapter) {
      _didJumpToInitialChapter = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(readerProvider(widget.bookId).notifier)
            .jumpToChapter(ic, charOffset: offset);
      });
    }
  }

  @override
  void didUpdateWidget(_ReaderShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 发生跳转（换章 / 跳书签）后清除阅读偏移记录，改用 state 的目标偏移定位
    if (oldWidget.state.jumpToken != widget.state.jumpToken) {
      _lastCharOffset = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final settings = widget.settings;
    // 定位偏移：优先用最近阅读偏移（保留切模式/改设置前的位置），否则用初始偏移
    final effectiveOffset = _lastCharOffset ?? state.initialCharOffset;
    final effectiveSegmentIndex = findSegmentIndexForChapterOffset(
      state.currentChapterSegments,
      state.currentChapter.startChar,
      effectiveOffset,
    );
    final effectiveSegmentText =
        effectiveSegmentIndex == state.initialSegmentIndex
        ? state.initialSegmentText
        : null;
    final textStyle = TextStyle(
      color: settings.theme.foreground,
      fontSize: settings.fontSize.size,
      height: settings.lineHeight.multiplier,
    );
    final searchContext = _searchNavigationVisible
        ? widget.searchContext
        : null;
    final activeSearchTarget = searchContext == null
        ? null
        : searchContext.targets[_activeSearchTargetIndex];

    // 当前章节内的所有书签 offset 集合：传给 _PaginatedView 判断"当前页是否有书签"
    final asyncBookmarks = ref.watch(bookmarksProvider(widget.bookId));
    final chapterBookmarkOffsets = asyncBookmarks.maybeWhen(
      data: (list) => list
          .where((b) => b.chapterIndex == state.currentChapterIndex)
          .map((b) => b.charOffset)
          .toSet(),
      orElse: () => <int>{},
    );

    return PopScope(
      // 系统返回键也先保存进度，再真正退出阅读页。
      canPop: _allowPopAfterSave,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _saveProgressAndPop(_lastCharOffset ?? effectiveOffset);
      },
      child: Scaffold(
        backgroundColor: settings.theme.background,
        drawer: ReaderDrawer(
          bookId: widget.bookId,
          chapters: state.chapters,
          currentChapterIndex: state.currentChapterIndex,
          onJump: (i, offset) => ref
              .read(readerProvider(widget.bookId).notifier)
              .jumpToChapter(i, charOffset: offset),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 公共回调参数（两种模式共用）
              void tapCenter() => setState(() => _menuVisible = !_menuVisible);
              void openChapters() => Scaffold.of(context).openDrawer();
              void openSettings() => showReaderSettingsSheet(context);
              Future<void> goBack(int charOffset) =>
                  _saveProgressAndPop(charOffset);
              final onPrevChapter = state.hasPrev
                  ? () => ref
                        .read(readerProvider(widget.bookId).notifier)
                        .prevChapter()
                  : null;
              final onNextChapter = state.hasNext
                  ? () => ref
                        .read(readerProvider(widget.bookId).notifier)
                        .nextChapter()
                  : null;
              // 记录最近阅读偏移并写库：非响应式更新 _lastCharOffset，
              // 避免每次翻页都触发 _ReaderShell 重建与重新分页
              void reportOffset(int offset) {
                _lastCharOffset = offset;
                ref
                    .read(readerProvider(widget.bookId).notifier)
                    .saveProgress(offset);
              }

              Future<String> loadSegment(int segmentIndex) => ref
                  .read(readerProvider(widget.bookId).notifier)
                  .readSegmentText(segmentIndex);

              late final Widget readerView;
              // 滚动模式：无需分页计算
              if (settings.readingMode == ReadingMode.scroll) {
                readerView = SegmentedScrollReaderView(
                  key: ValueKey(
                    's-${state.book.id}-${state.currentChapterIndex}-${state.jumpToken}-${settings.fontSize.name}-${settings.lineHeight.name}',
                  ),
                  segments: state.currentChapterSegments,
                  chapterStartChar: state.currentChapter.startChar,
                  initialSegmentIndex: effectiveSegmentIndex,
                  initialSegmentText: effectiveSegmentText,
                  loadSegment: loadSegment,
                  padding: _padding,
                  textStyle: textStyle,
                  themeBg: settings.theme.background,
                  themeFg: settings.theme.foreground,
                  chapterTitle: state.currentChapter.title,
                  menuVisible: _menuVisible,
                  initialCharOffset: effectiveOffset,
                  onCharOffsetChanged: reportOffset,
                  onTapCenter: tapCenter,
                  onPrevChapter: onPrevChapter,
                  onNextChapter: onNextChapter,
                  onOpenChapters: openChapters,
                  onOpenSettings: openSettings,
                  onAddBookmark: (charOffset) =>
                      _addBookmark(state.currentChapterIndex, charOffset),
                  onBack: goBack,
                  searchQuery: searchContext?.query,
                  activeSearchOffset:
                      activeSearchTarget?.chapterIndex ==
                          state.currentChapterIndex
                      ? activeSearchTarget?.charOffset
                      : null,
                  activeSearchLength:
                      activeSearchTarget?.chapterIndex ==
                          state.currentChapterIndex
                      ? activeSearchTarget?.matchLength
                      : null,
                );
              } else {
                // 翻页模式：按页探测有限文本窗口，不再同步分页整个章节。
                final contentWidth = constraints.maxWidth - _padding.horizontal;
                final contentHeight = constraints.maxHeight - _padding.vertical;
                readerView = SegmentedPaginatedReaderView(
                  key: ValueKey(
                    'p-${state.book.id}-${state.currentChapterIndex}-${state.jumpToken}-${settings.fontSize.name}-${settings.lineHeight.name}-${constraints.maxWidth.toInt()}x${constraints.maxHeight.toInt()}',
                  ),
                  segments: state.currentChapterSegments,
                  chapterStartChar: state.currentChapter.startChar,
                  initialSegmentIndex: effectiveSegmentIndex,
                  initialSegmentText: effectiveSegmentText,
                  initialCharOffset: effectiveOffset,
                  loadSegment: loadSegment,
                  contentWidth: contentWidth,
                  contentHeight: contentHeight,
                  padding: _padding,
                  textStyle: textStyle,
                  themeBg: settings.theme.background,
                  themeFg: settings.theme.foreground,
                  chapterTitle: state.currentChapter.title,
                  menuVisible: _menuVisible,
                  chapterBookmarkOffsets: chapterBookmarkOffsets,
                  onCharOffsetChanged: reportOffset,
                  onTapCenter: tapCenter,
                  onPrevChapter: onPrevChapter,
                  onNextChapter: onNextChapter,
                  onOpenChapters: openChapters,
                  onOpenSettings: openSettings,
                  onAddBookmark: (charOffset) =>
                      _addBookmark(state.currentChapterIndex, charOffset),
                  onBack: goBack,
                  searchQuery: searchContext?.query,
                  activeSearchOffset:
                      activeSearchTarget?.chapterIndex ==
                          state.currentChapterIndex
                      ? activeSearchTarget?.charOffset
                      : null,
                  activeSearchLength:
                      activeSearchTarget?.chapterIndex ==
                          state.currentChapterIndex
                      ? activeSearchTarget?.matchLength
                      : null,
                );
              }

              return Stack(
                children: [
                  Positioned.fill(child: readerView),
                  if (searchContext != null && !_menuVisible)
                    Positioned(
                      top: AppSpacing.xs,
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      child: _ReaderSearchNavigationBar(
                        query: searchContext.query,
                        current: _activeSearchTargetIndex + 1,
                        total: searchContext.targets.length,
                        background: settings.theme.background,
                        foreground: settings.theme.foreground,
                        onPrevious: _activeSearchTargetIndex > 0
                            ? () => _jumpToSearchTarget(-1)
                            : null,
                        onNext:
                            _activeSearchTargetIndex + 1 <
                                searchContext.targets.length
                            ? () => _jumpToSearchTarget(1)
                            : null,
                        onClose: () =>
                            setState(() => _searchNavigationVisible = false),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _jumpToSearchTarget(int delta) async {
    final searchContext = widget.searchContext;
    if (!_searchNavigationVisible || searchContext == null) return;
    final next = (_activeSearchTargetIndex + delta).clamp(
      0,
      searchContext.targets.length - 1,
    );
    if (next == _activeSearchTargetIndex) return;
    final target = searchContext.targets[next];
    setState(() {
      _activeSearchTargetIndex = next;
      _menuVisible = false;
    });
    await ref
        .read(readerProvider(widget.bookId).notifier)
        .jumpToChapter(target.chapterIndex, charOffset: target.charOffset);
  }

  // 退出阅读页前保存"当前可见位置"。
  // 仅依赖章节内偏移，不关心具体阅读模式，便于翻页 / 滚动模式共用。
  Future<void> _saveProgressAndPop(int charOffset) async {
    if (_savingAndPopping) return;
    _savingAndPopping = true;
    _lastCharOffset = charOffset;
    try {
      await ref
          .read(readerProvider(widget.bookId).notifier)
          .saveProgress(charOffset);
    } catch (_) {
      // 保存失败不阻断返回：下次翻页/跳转仍会继续尝试写入进度。
    }
    if (!mounted) return;
    setState(() => _allowPopAfterSave = true);
    Navigator.of(context).pop();
  }

  // 弹对话框输入备注（可留空），保存后自动收起菜单回到阅读
  Future<void> _addBookmark(int chapterIndex, int charOffset) async {
    final note = await showDialog<String?>(
      context: context,
      builder: (_) => const _BookmarkNoteDialog(),
    );
    if (note == null) return; // 用户取消
    await ref
        .read(bookmarksProvider(widget.bookId).notifier)
        .add(
          chapterIndex: chapterIndex,
          charOffset: charOffset,
          note: note.isEmpty ? null : note,
        );
    if (mounted) {
      setState(() => _menuVisible = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.bookmarkAdded),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}

// 添加书签时的备注对话框：留空确认会保存为无备注
class _BookmarkNoteDialog extends StatefulWidget {
  const _BookmarkNoteDialog();

  @override
  State<_BookmarkNoteDialog> createState() => _BookmarkNoteDialogState();
}

class _BookmarkNoteDialogState extends State<_BookmarkNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.addBookmark),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        decoration: InputDecoration(
          hintText: context.l10n.bookmarkNoteHint,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}

class _ReaderSearchNavigationBar extends StatelessWidget {
  final String query;
  final int current;
  final int total;
  final Color background;
  final Color foreground;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  const _ReaderSearchNavigationBar({
    required this.query,
    required this.current,
    required this.total,
    required this.background,
    required this.foreground,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final panel = Color.alphaBlend(
      foreground.withValues(alpha: 0.09),
      background,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: panel.withValues(alpha: 0.98),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: foreground.withValues(alpha: 0.14)),
          ),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.search, size: 18, color: foreground),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  context.l10n.searchMatchPosition(current, total),
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.68),
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.previousSearchMatch,
                  visualDensity: VisualDensity.compact,
                  color: foreground,
                  disabledColor: foreground.withValues(alpha: 0.25),
                  onPressed: onPrevious,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                ),
                IconButton(
                  tooltip: context.l10n.nextSearchMatch,
                  visualDensity: VisualDensity.compact,
                  color: foreground,
                  disabledColor: foreground.withValues(alpha: 0.25),
                  onPressed: onNext,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                ),
                IconButton(
                  tooltip: context.l10n.closeSearchNavigation,
                  visualDensity: VisualDensity.compact,
                  color: foreground,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderText extends StatelessWidget {
  static const _maxPassiveHighlights = 256;

  final String text;
  final int chapterOffset;
  final TextStyle style;
  final Color background;
  final Color foreground;
  final String? searchQuery;
  final int? activeSearchOffset;
  final int? activeSearchLength;

  const _ReaderText({
    required this.text,
    required this.chapterOffset,
    required this.style,
    required this.background,
    required this.foreground,
    this.searchQuery,
    this.activeSearchOffset,
    this.activeSearchLength,
  });

  @override
  Widget build(BuildContext context) {
    final query = searchQuery;
    final layout = ReaderTextLayout.of(context);
    final span = _highlightedSpan(query);
    return Text.rich(
      span,
      style: style,
      textScaler: layout.textScaler,
      textDirection: layout.textDirection,
      locale: layout.locale,
      textHeightBehavior: layout.textHeightBehavior,
      textWidthBasis: layout.textWidthBasis,
    );
  }

  TextSpan _highlightedSpan(String? query) {
    if (query == null || query.isEmpty || text.isEmpty) {
      return TextSpan(text: text);
    }

    final passiveMatches = findTextMatches(
      text,
      query,
      maxMatches: _maxPassiveHighlights,
    );
    final activeStart = activeSearchOffset == null
        ? null
        : activeSearchOffset! - chapterOffset;
    final activeEnd = activeStart == null
        ? null
        : activeStart + (activeSearchLength ?? 0);
    final boundaries = <int>{0, text.length};
    for (final match in passiveMatches) {
      boundaries
        ..add(match.offset)
        ..add(match.endOffset);
    }
    if (activeStart != null && activeEnd != null) {
      final start = activeStart.clamp(0, text.length);
      final end = activeEnd.clamp(0, text.length);
      if (end > start) {
        boundaries
          ..add(start)
          ..add(end);
      }
    }

    final points = boundaries.toList()..sort();
    final passiveBackground = Color.alphaBlend(
      foreground.withValues(alpha: 0.14),
      background,
    );
    final activeBackground = Color.alphaBlend(
      const Color(0xFFF4B400).withValues(alpha: 0.52),
      background,
    );
    final spans = <TextSpan>[];
    for (var index = 0; index + 1 < points.length; index++) {
      final start = points[index];
      final end = points[index + 1];
      if (end <= start) continue;
      final active =
          activeStart != null &&
          activeEnd != null &&
          start < activeEnd &&
          end > activeStart;
      final passive = passiveMatches.any(
        (match) => start < match.endOffset && end > match.offset,
      );
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: active
              ? TextStyle(
                  backgroundColor: activeBackground,
                  // 高亮只改变颜色，避免字重变化使最终正文与分页度量不一致。
                )
              : passive
              ? TextStyle(backgroundColor: passiveBackground)
              : null,
        ),
      );
    }
    return TextSpan(children: spans);
  }
}

class _ChapterEndCue extends StatelessWidget {
  final bool hasNext;
  final Color foreground;

  const _ChapterEndCue({required this.hasNext, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Text(
        hasNext ? context.l10n.continueToNextChapter : context.l10n.endOfBook,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foreground.withValues(alpha: 0.52),
          fontSize: 12,
        ),
      ),
    );
  }
}

class SegmentedPaginatedReaderView extends StatefulWidget {
  final List<RenderSegment> segments;
  final int chapterStartChar;
  final int initialSegmentIndex;
  final String? initialSegmentText;
  final int initialCharOffset;
  final SegmentTextReader loadSegment;
  final double contentWidth;
  final double contentHeight;
  final EdgeInsets padding;
  final TextStyle textStyle;
  final Color themeBg;
  final Color themeFg;
  final String chapterTitle;
  final bool menuVisible;
  // 当前章节内所有书签的字符偏移；用于判断"当前页是否含书签"
  final Set<int> chapterBookmarkOffsets;
  final void Function(int) onCharOffsetChanged;
  final VoidCallback onTapCenter;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;
  // 加书签：传入当前页起始的章节内偏移
  final void Function(int charOffset) onAddBookmark;
  final Future<void> Function(int charOffset) onBack;
  final String? searchQuery;
  final int? activeSearchOffset;
  final int? activeSearchLength;

  const SegmentedPaginatedReaderView({
    super.key,
    required this.segments,
    required this.chapterStartChar,
    required this.initialSegmentIndex,
    required this.initialSegmentText,
    required this.initialCharOffset,
    required this.loadSegment,
    required this.contentWidth,
    required this.contentHeight,
    required this.padding,
    required this.textStyle,
    required this.themeBg,
    required this.themeFg,
    required this.chapterTitle,
    required this.menuVisible,
    required this.chapterBookmarkOffsets,
    required this.onCharOffsetChanged,
    required this.onTapCenter,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onOpenChapters,
    required this.onOpenSettings,
    required this.onAddBookmark,
    required this.onBack,
    this.searchQuery,
    this.activeSearchOffset,
    this.activeSearchLength,
  });

  @override
  State<SegmentedPaginatedReaderView> createState() => _PaginatedViewState();
}

class _PaginatedViewState extends State<SegmentedPaginatedReaderView> {
  late final SegmentTextSource _source = SegmentTextSource(
    segments: widget.segments,
    chapterStartChar: widget.chapterStartChar,
    readSegment: widget.loadSegment,
    initialSegmentIndex: widget.initialSegmentIndex,
    initialSegmentText: widget.initialSegmentText,
  );
  LazyChapterPaginator? _paginator;
  int _layoutGeneration = 0;
  late int _layoutAnchorOffset = widget.initialCharOffset;
  final List<ReaderPageSlice> _backPages = [];
  final List<ReaderPageSlice> _forwardPages = [];
  ReaderPageSlice? _current;
  Object? _loadError;
  bool _loading = true;
  bool _movingForward = true;

  @override
  void initState() {
    super.initState();
    _source.prefetchAround(widget.initialSegmentIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configurePaginator();
  }

  @override
  void didUpdateWidget(SegmentedPaginatedReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configurePaginator();
  }

  void _configurePaginator() {
    final layout = ReaderTextLayout.of(context);
    final style = DefaultTextStyle.of(context).style.merge(widget.textStyle);
    final previous = _paginator;
    if (previous != null &&
        previous.layout == layout &&
        previous.style == style &&
        previous.contentWidth == widget.contentWidth &&
        previous.contentHeight == widget.contentHeight) {
      return;
    }

    // 缩放、字体和可用空间变化后从当前字符重新排页，旧异步结果不得覆盖新布局。
    final offset = _current?.startOffset ?? _layoutAnchorOffset;
    _layoutAnchorOffset = offset;
    final generation = ++_layoutGeneration;
    final paginator = LazyChapterPaginator(
      source: _source,
      style: style,
      layout: layout,
      contentWidth: widget.contentWidth,
      contentHeight: widget.contentHeight,
    );
    _paginator = paginator;
    _backPages.clear();
    _forwardPages.clear();
    _current = null;
    _loadError = null;
    _loading = true;
    unawaited(_loadInitialPage(paginator, offset, generation));
  }

  Future<void> _loadInitialPage(
    LazyChapterPaginator paginator,
    int offset,
    int generation,
  ) async {
    try {
      final page = await paginator.pageFrom(offset);
      if (!mounted || generation != _layoutGeneration) return;
      setState(() {
        _current = page;
        _layoutAnchorOffset = page.startOffset;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _layoutGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _goPrev() async {
    final current = _current;
    if (_loading || current == null) return;
    if (current.startOffset <= 0) {
      widget.onPrevChapter?.call();
      return;
    }
    await _moveTo(
      forward: false,
      load: () => _backPages.isNotEmpty
          ? Future.value(_backPages.removeLast())
          : _paginator!.pageEndingAt(current.startOffset),
    );
  }

  Future<void> _goNext() async {
    final current = _current;
    if (_loading || current == null) return;
    if (current.endOffset >= _source.chapterCharCount) {
      widget.onNextChapter?.call();
      return;
    }
    await _moveTo(
      forward: true,
      load: () => _forwardPages.isNotEmpty
          ? Future.value(_forwardPages.removeLast())
          : _paginator!.pageFrom(current.endOffset),
    );
  }

  Future<void> _moveTo({
    required bool forward,
    required Future<ReaderPageSlice> Function() load,
  }) async {
    final previous = _current;
    if (previous == null) return;
    final generation = _layoutGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
      _movingForward = forward;
    });
    try {
      final page = await load();
      if (!mounted || generation != _layoutGeneration) return;
      if (forward) {
        _backPages.add(previous);
      } else {
        _forwardPages.add(previous);
      }
      _trimHistory(forward ? _backPages : _forwardPages);
      setState(() {
        _current = page;
        _layoutAnchorOffset = page.startOffset;
        _loading = false;
      });
      widget.onCharOffsetChanged(page.startOffset);
      _source.prefetchAround(_source.segmentIndexForOffset(page.startOffset));
    } catch (error) {
      if (!mounted || generation != _layoutGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _trimHistory(List<ReaderPageSlice> pages) {
    const limit = ReaderRenderPolicy.defaultPageHistoryCount;
    if (pages.length > limit) pages.removeRange(0, pages.length - limit);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = _current;
    final progress = current == null || _source.chapterCharCount == 0
        ? 0.0
        : (current.startOffset / _source.chapterCharCount).clamp(0.0, 1.0);
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: AppMotion.fast,
            switchInCurve: AppMotion.easeOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(_movingForward ? 0.04 : -0.04, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _loadError != null
                ? Center(
                    key: const ValueKey('page-error'),
                    child: Text(
                      context.l10n.openBookFailed(_loadError!),
                      style: widget.textStyle,
                    ),
                  )
                : current == null
                ? const Center(
                    key: ValueKey('page-loading'),
                    child: CircularProgressIndicator(),
                  )
                : Padding(
                    key: ValueKey(current.startOffset),
                    padding: widget.padding,
                    child: _ReaderText(
                      text: current.text,
                      chapterOffset: current.startOffset,
                      style: widget.textStyle,
                      background: widget.themeBg,
                      foreground: widget.themeFg,
                      searchQuery: widget.searchQuery,
                      activeSearchOffset: widget.activeSearchOffset,
                      activeSearchLength: widget.activeSearchLength,
                    ),
                  ),
          ),
        ),
        // 透明手势层
        // 菜单隐藏：左/中/右 三栏（上一页 / 切换菜单 / 下一页）
        // 菜单显示：整层响应点击，收起菜单回到阅读
        // 放在顶/底栏之前 → 顶/底栏 z 序更高，按钮点击优先命中，不会被手势层吞掉
        Positioned.fill(
          child: widget.menuVisible
              ? GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onTapCenter,
                )
              : Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => unawaited(_goPrev()),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: widget.onTapCenter,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => unawaited(_goNext()),
                      ),
                    ),
                  ],
                ),
        ),
        // 顶部章节标题：显示/隐藏时用滑入淡入，减少菜单突兀感
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _ReaderTopBar(
            visible: widget.menuVisible,
            title: widget.chapterTitle,
            background: widget.themeBg,
            foreground: widget.themeFg,
            onBack: () =>
                widget.onBack(current?.startOffset ?? _layoutAnchorOffset),
          ),
        ),
        // 总页数未知时只显示章节进度，避免为页码预先布局整章。
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: widget.themeFg.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ),
        ),
        // 右上角书签标记：仅当前页范围内含书签时显示
        // 菜单显示时让位给顶部栏，避免重叠
        Positioned(
          top: AppSpacing.sm,
          right: AppSpacing.sm,
          child: AnimatedSwitcher(
            duration: AppMotion.fast,
            switchInCurve: AppMotion.easeOut,
            switchOutCurve: AppMotion.easeInOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: !widget.menuVisible && _currentPageHasBookmark(current)
                ? Icon(
                    Icons.bookmark,
                    key: const ValueKey('bookmark-visible'),
                    size: 20,
                    color: widget.themeFg.withValues(alpha: 0.6),
                  )
                : const SizedBox(
                    key: ValueKey('bookmark-hidden'),
                    width: 20,
                    height: 20,
                  ),
          ),
        ),
        // 底部菜单：保留固定位置，只让内容做淡入滑动，避免布局跳变
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _ReaderBottomBar(
            visible: widget.menuVisible,
            previousLabel: l10n.previousChapter,
            nextLabel: l10n.nextChapter,
            contentsLabel: l10n.contentsTitle,
            bookmarkLabel: l10n.bookmarksTitle,
            settingsLabel: l10n.readingSettingsSection,
            background: widget.themeBg,
            foreground: widget.themeFg,
            onPrevChapter: widget.onPrevChapter,
            onNextChapter: widget.onNextChapter,
            onOpenChapters: widget.onOpenChapters,
            onAddBookmark: () => widget.onAddBookmark(
              current?.startOffset ?? _layoutAnchorOffset,
            ),
            onOpenSettings: widget.onOpenSettings,
          ),
        ),
      ],
    );
  }

  // 当前页 [pageStart, pageEnd) 范围内是否有书签
  bool _currentPageHasBookmark(ReaderPageSlice? page) {
    if (page == null || widget.chapterBookmarkOffsets.isEmpty) return false;
    for (final off in widget.chapterBookmarkOffsets) {
      if (off >= page.startOffset && off < page.endOffset) return true;
    }
    return false;
  }
}

// 阅读页菜单顶部栏：只负责展示章节标题与返回按钮，动效由组件内部统一处理。
class _ReaderTopBar extends StatelessWidget {
  final bool visible;
  final String title;
  final Color background;
  final Color foreground;
  final VoidCallback onBack;

  const _ReaderTopBar({
    required this.visible,
    required this.title,
    required this.background,
    required this.foreground,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: AppMotion.normal,
        curve: AppMotion.easeOut,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background.withValues(alpha: 0.92),
              border: Border(
                bottom: BorderSide(color: foreground.withValues(alpha: 0.1)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    color: foreground,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 阅读页底部操作栏：翻页模式和滚动模式共用，避免两套菜单动效不一致。
class _ReaderBottomBar extends StatelessWidget {
  final bool visible;
  final String previousLabel;
  final String nextLabel;
  final String contentsLabel;
  final String bookmarkLabel;
  final String settingsLabel;
  final Color background;
  final Color foreground;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onOpenChapters;
  final VoidCallback onAddBookmark;
  final VoidCallback onOpenSettings;

  const _ReaderBottomBar({
    required this.visible,
    required this.previousLabel,
    required this.nextLabel,
    required this.contentsLabel,
    required this.bookmarkLabel,
    required this.settingsLabel,
    required this.background,
    required this.foreground,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onOpenChapters,
    required this.onAddBookmark,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final panelColor = Color.alphaBlend(
      foreground.withValues(alpha: 0.07),
      background,
    );
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1),
        duration: AppMotion.normal,
        curve: AppMotion.easeOut,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: panelColor.withValues(alpha: 0.98),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: foreground.withValues(alpha: 0.12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: foreground.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        _ReaderChapterButton(
                          icon: Icons.chevron_left,
                          label: previousLabel,
                          foreground: foreground,
                          onTap: onPrevChapter,
                        ),
                        Expanded(
                          child: _ReaderMenuButton(
                            icon: Icons.list_alt_outlined,
                            label: contentsLabel,
                            foreground: foreground,
                            onTap: onOpenChapters,
                          ),
                        ),
                        Expanded(
                          child: _ReaderMenuButton(
                            icon: Icons.bookmark_add_outlined,
                            label: bookmarkLabel,
                            foreground: foreground,
                            onTap: onAddBookmark,
                          ),
                        ),
                        Expanded(
                          child: _ReaderMenuButton(
                            icon: Icons.text_fields,
                            label: settingsLabel,
                            foreground: foreground,
                            onTap: onOpenSettings,
                          ),
                        ),
                        _ReaderChapterButton(
                          icon: Icons.chevron_right,
                          label: nextLabel,
                          foreground: foreground,
                          onTap: onNextChapter,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final VoidCallback onTap;

  const _ReaderMenuButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm - 2,
          horizontal: AppSpacing.xs,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// 上一章 / 下一章只保留图标与 tooltip，视觉权重低于中间三个一级操作。
class _ReaderChapterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final VoidCallback? onTap;

  const _ReaderChapterButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      color: foreground.withValues(alpha: 0.62),
      disabledColor: foreground.withValues(alpha: 0.22),
      icon: Icon(icon, size: 22),
    );
  }
}

// ─── 滚动阅读视图 ────────────────────────────────────────────────

class SegmentedScrollReaderView extends StatefulWidget {
  final List<RenderSegment> segments;
  final int chapterStartChar;
  final int initialSegmentIndex;
  final String? initialSegmentText;
  final SegmentTextReader loadSegment;
  final ScrollController? controller;
  final EdgeInsets padding;
  final TextStyle textStyle;
  final Color themeBg;
  final Color themeFg;
  final String chapterTitle;
  final bool menuVisible;
  final int initialCharOffset;
  final void Function(int) onCharOffsetChanged;
  final VoidCallback onTapCenter;
  final VoidCallback? onPrevChapter;
  final Future<void> Function()? onNextChapter;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;
  final void Function(int charOffset) onAddBookmark;
  final Future<void> Function(int charOffset) onBack;
  final String? searchQuery;
  final int? activeSearchOffset;
  final int? activeSearchLength;

  const SegmentedScrollReaderView({
    super.key,
    required this.segments,
    required this.chapterStartChar,
    required this.initialSegmentIndex,
    required this.initialSegmentText,
    required this.loadSegment,
    this.controller,
    required this.padding,
    required this.textStyle,
    required this.themeBg,
    required this.themeFg,
    required this.chapterTitle,
    required this.menuVisible,
    required this.initialCharOffset,
    required this.onCharOffsetChanged,
    required this.onTapCenter,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onOpenChapters,
    required this.onOpenSettings,
    required this.onAddBookmark,
    required this.onBack,
    this.searchQuery,
    this.activeSearchOffset,
    this.activeSearchLength,
  });

  @override
  State<SegmentedScrollReaderView> createState() => _ScrollViewState();
}

class _ScrollViewState extends State<SegmentedScrollReaderView> {
  late final ScrollController _ctrl;
  late final SegmentTextSource _source = SegmentTextSource(
    segments: widget.segments,
    chapterStartChar: widget.chapterStartChar,
    readSegment: widget.loadSegment,
    initialSegmentIndex: widget.initialSegmentIndex,
    initialSegmentText: widget.initialSegmentText,
  );
  final GlobalKey _centerKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _segmentKeys = {};
  final Set<int> _loadedSegments = {};
  bool _didPositionInitially = false;
  bool _userScrollingForward = false;
  bool _changingChapter = false;
  Timer? _progressReportTimer;
  late int _latestCharOffset = widget.initialCharOffset;
  // 阅读进度百分比：用 ValueNotifier 单独驱动底部百分比刷新，
  // 避免滚动时 setState 重建正文分片。
  final ValueNotifier<double> _progress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? ScrollController();
    _ctrl.addListener(_onScroll);
    final count = _source.chapterCharCount;
    _progress.value = count == 0
        ? 0
        : (widget.initialCharOffset / count).clamp(0.0, 1.0);
    _source.prefetchAround(widget.initialSegmentIndex);
  }

  @override
  void dispose() {
    _progressReportTimer?.cancel();
    if (widget.controller == null) _ctrl.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _currentCharOffset;
    _latestCharOffset = offset;
    final count = _source.chapterCharCount;
    final p = count == 0 ? 0.0 : (offset / count).clamp(0.0, 1.0);
    if ((p - _progress.value).abs() > 0.001) _progress.value = p;
    _source.prefetchAround(_source.segmentIndexForOffset(offset));
    _progressReportTimer?.cancel();
    _progressReportTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) widget.onCharOffsetChanged(_latestCharOffset);
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse) {
        _userScrollingForward = true;
      } else if (notification.direction == ScrollDirection.forward) {
        _userScrollingForward = false;
      }
    }
    if (notification is ScrollEndNotification) {
      _latestCharOffset = _currentCharOffset;
      widget.onCharOffsetChanged(_latestCharOffset);
      if (_userScrollingForward &&
          notification.metrics.extentAfter <= 1 &&
          widget.onNextChapter != null) {
        _userScrollingForward = false;
        unawaited(_advanceToNextChapter());
      }
    }
    return false;
  }

  Future<void> _advanceToNextChapter() async {
    final next = widget.onNextChapter;
    if (_changingChapter || next == null) return;
    _changingChapter = true;
    _latestCharOffset = _source.chapterCharCount;
    widget.onCharOffsetChanged(_latestCharOffset);
    try {
      await next();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.openBookFailed(error))),
        );
      }
    } finally {
      _changingChapter = false;
    }
  }

  Future<void> _positionInitially() async {
    if (!mounted || !_ctrl.hasClients) return;
    final segment = widget.segments[widget.initialSegmentIndex];
    final box = _boxForSegment(widget.initialSegmentIndex);
    if (box == null || segment.charCount == 0) return;
    final viewport = RenderAbstractViewport.of(box);
    final segmentStart = segment.startChar - widget.chapterStartChar;
    final localOffset = (widget.initialCharOffset - segmentStart).clamp(
      0,
      segment.charCount,
    );
    final textOffset = ReaderTextPosition.verticalOffsetForCharacter(
      box,
      localOffset,
    );
    if (textOffset == null) return;
    final segmentOffset = viewport.getOffsetToReveal(box, 0).offset;
    final target = segmentOffset + textOffset;
    final position = _ctrl.position;
    _ctrl.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  RenderBox? _boxForSegment(int index) =>
      _segmentKeys[index]?.currentContext?.findRenderObject() as RenderBox?;

  int get _currentCharOffset {
    if (!_ctrl.hasClients || widget.segments.isEmpty) {
      return widget.initialCharOffset;
    }
    int? selectedIndex;
    RenderBox? selectedBox;
    var nearestTop = double.infinity;
    for (final entry in _segmentKeys.entries) {
      // 占位和错误提示都不是正文，不能用它们覆盖用户已经保存的阅读位置。
      if (!_loadedSegments.contains(entry.key)) continue;
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || box.size.height <= 0) continue;
      final viewport = RenderAbstractViewport.of(box);
      final itemStart = viewport.getOffsetToReveal(box, 0).offset;
      final itemEnd = itemStart + box.size.height;
      if (itemStart <= _ctrl.offset && itemEnd > _ctrl.offset) {
        selectedIndex = entry.key;
        selectedBox = box;
        break;
      }
      final distance = (itemStart - _ctrl.offset).abs();
      if (distance < nearestTop) {
        nearestTop = distance;
        selectedIndex = entry.key;
        selectedBox = box;
      }
    }
    if (selectedIndex == null || selectedBox == null) {
      return _latestCharOffset;
    }
    final viewport = RenderAbstractViewport.of(selectedBox);
    final itemStart = viewport.getOffsetToReveal(selectedBox, 0).offset;
    final segment = widget.segments[selectedIndex];
    final segmentStart = segment.startChar - widget.chapterStartChar;
    final localOffset = ReaderTextPosition.characterAtVerticalOffset(
      selectedBox,
      _ctrl.offset - itemStart,
    );
    if (localOffset == null) return _latestCharOffset;
    return (segmentStart + localOffset.clamp(0, segment.charCount)).clamp(
      0,
      _source.chapterCharCount,
    );
  }

  Widget _segmentItem(BuildContext context, int index) {
    final key = _segmentKeys.putIfAbsent(index, GlobalKey.new);
    final top = index == 0 ? widget.padding.top : 0.0;
    final bottom = index == widget.segments.length - 1
        ? widget.padding.bottom
        : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.padding.left,
        top,
        widget.padding.right,
        bottom,
      ),
      child: FutureBuilder<String>(
        future: _source.textAt(index),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            _loadedSegments.remove(index);
            return Text(
              context.l10n.openBookFailed(snapshot.error!),
              key: key,
              style: widget.textStyle,
            );
          }
          final text = snapshot.data;
          if (text == null) {
            _loadedSegments.remove(index);
            return SizedBox(
              key: key,
              // 使用字符数估算占位高度，避免短占位让 Sliver 一次触发大量远处分片读取。
              height: _estimatedSegmentHeight(context, index),
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          _loadedSegments.add(index);
          if (index == widget.initialSegmentIndex && !_didPositionInitially) {
            _didPositionInitially = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _positionInitially(),
            );
          }
          final segment = widget.segments[index];
          return KeyedSubtree(
            key: key,
            child: _ReaderText(
              text: text,
              chapterOffset: segment.startChar - widget.chapterStartChar,
              style: widget.textStyle,
              background: widget.themeBg,
              foreground: widget.themeFg,
              searchQuery: widget.searchQuery,
              activeSearchOffset: widget.activeSearchOffset,
              activeSearchLength: widget.activeSearchLength,
            ),
          );
        },
      ),
    );
  }

  double _estimatedSegmentHeight(BuildContext context, int index) {
    final availableWidth =
        MediaQuery.sizeOf(context).width - widget.padding.horizontal;
    final fontSize = widget.textStyle.fontSize ?? 16;
    final lineHeight = widget.textStyle.height ?? 1.2;
    final approximateGlyphWidth = fontSize * 0.65;
    final charsPerLine = (availableWidth / approximateGlyphWidth).clamp(
      1.0,
      double.infinity,
    );
    final lines = (widget.segments[index].charCount / charsPerLine).ceil();
    return (lines * fontSize * lineHeight).clamp(72.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      children: [
        // center 让任意目标分片都能作为初始位置，前后列表仍保持连续滚动和懒构建。
        Positioned.fill(
          child: SizedBox(
            key: _viewportKey,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onTapCenter,
                child: CustomScrollView(
                  controller: _ctrl,
                  center: _centerKey,
                  slivers: [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _segmentItem(
                          context,
                          widget.initialSegmentIndex - index - 1,
                        ),
                        childCount: widget.initialSegmentIndex,
                      ),
                    ),
                    SliverList(
                      key: _centerKey,
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _segmentItem(
                          context,
                          widget.initialSegmentIndex + index,
                        ),
                        childCount:
                            widget.segments.length - widget.initialSegmentIndex,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _ChapterEndCue(
                        hasNext: widget.onNextChapter != null,
                        foreground: widget.themeFg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 顶部章节标题：滚动阅读与翻页阅读保持同一套菜单动效
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _ReaderTopBar(
            visible: widget.menuVisible,
            title: widget.chapterTitle,
            background: widget.themeBg,
            foreground: widget.themeFg,
            onBack: () => widget.onBack(_currentCharOffset),
          ),
        ),
        // 底部阅读进度百分比：仅此小部件随滚动刷新
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, progress, _) => Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: widget.themeFg.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        // 底部菜单：保留固定位置，只让内容做淡入滑动，避免布局跳变
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _ReaderBottomBar(
            visible: widget.menuVisible,
            previousLabel: l10n.previousChapter,
            nextLabel: l10n.nextChapter,
            contentsLabel: l10n.contentsTitle,
            bookmarkLabel: l10n.bookmarksTitle,
            settingsLabel: l10n.readingSettingsSection,
            background: widget.themeBg,
            foreground: widget.themeFg,
            onPrevChapter: widget.onPrevChapter,
            onNextChapter: widget.onNextChapter,
            onOpenChapters: widget.onOpenChapters,
            onAddBookmark: () => widget.onAddBookmark(_currentCharOffset),
            onOpenSettings: widget.onOpenSettings,
          ),
        ),
      ],
    );
  }
}
