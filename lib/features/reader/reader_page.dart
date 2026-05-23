import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reader_settings.dart';
import '../../shared/l10n/app_l10n.dart';
import '../library/library_provider.dart';
import '../settings/settings_page.dart';
import '../settings/settings_provider.dart';
import 'bookmark_provider.dart';
import 'pagination.dart';
import 'reader_provider.dart';
import 'widgets/reader_drawer.dart';

class ReaderPage extends ConsumerWidget {
  final int bookId;
  // 可选：从搜索跳转时直接定位到指定章节与字符
  final int? initialChapterIndex;
  final int? initialCharOffset;

  const ReaderPage({
    super.key,
    required this.bookId,
    this.initialChapterIndex,
    this.initialCharOffset,
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

  const _ReaderShell({
    required this.bookId,
    required this.state,
    required this.settings,
    this.initialChapterIndex,
    this.initialCharOffset,
  });

  @override
  ConsumerState<_ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends ConsumerState<_ReaderShell> {
  bool _menuVisible = false;
  bool _didJumpToInitialChapter = false;

  // 章节内最近上报的阅读偏移：翻页/滚动时更新（非响应式，不触发重建）。
  // 切换阅读模式、改字号等导致视图重建时用它保留当前位置；发生跳转后置空。
  int? _lastCharOffset;

  // 分页结果缓存：仅当 (章节/字号/行距/可用宽高) 任一变化时重算
  // 同一 _ReaderShell 内加书签等无关 rebuild 会触发 build()，
  // 但分页输入未变，复用缓存避免主线程同步重新跑 TextPainter layout
  Pagination? _cachedPagination;
  String? _paginationCacheKey;

  // 内边距：上下留出顶部菜单与页码空间
  static const _padding = EdgeInsets.fromLTRB(20, 48, 20, 32);

  @override
  void initState() {
    super.initState();
    // 如果是从搜索跳转，进入后跳转到指定章节
    final ic = widget.initialChapterIndex;
    if (ic != null && !_didJumpToInitialChapter) {
      _didJumpToInitialChapter = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(readerProvider(widget.bookId).notifier)
            .jumpToChapter(ic, charOffset: widget.initialCharOffset ?? 0);
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
  void dispose() {
    // 离开阅读页时刷新书架：阅读时已写入 last_read_at，
    // 让书架的"最近阅读"排序与未读标签在返回后立即生效
    ref.invalidate(libraryProvider);
    super.dispose();
  }

  // 按 (章节/字号/行距/可用宽高) 缓存分页结果；颜色等不影响布局，不入键
  Pagination _paginate({
    required String text,
    required TextStyle style,
    required double contentWidth,
    required double contentHeight,
    required int chapterIndex,
    required String fontSizeName,
    required String lineHeightName,
  }) {
    final key =
        '$chapterIndex|$fontSizeName|$lineHeightName|${contentWidth.toInt()}|${contentHeight.toInt()}';
    if (key == _paginationCacheKey && _cachedPagination != null) {
      return _cachedPagination!;
    }
    final p = TextPaginator.paginate(
      text: text,
      style: style,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
    );
    _paginationCacheKey = key;
    _cachedPagination = p;
    return p;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final settings = widget.settings;
    // 定位偏移：优先用最近阅读偏移（保留切模式/改设置前的位置），否则用初始偏移
    final effectiveOffset = _lastCharOffset ?? state.initialCharOffset;
    final textStyle = TextStyle(
      color: settings.theme.foreground,
      fontSize: settings.fontSize.size,
      height: settings.lineHeight.multiplier,
    );

    // 当前章节内的所有书签 offset 集合：传给 _PaginatedView 判断"当前页是否有书签"
    final asyncBookmarks = ref.watch(bookmarksProvider(widget.bookId));
    final chapterBookmarkOffsets = asyncBookmarks.maybeWhen(
      data: (list) => list
          .where((b) => b.chapterIndex == state.currentChapterIndex)
          .map((b) => b.charOffset)
          .toSet(),
      orElse: () => <int>{},
    );

    return Scaffold(
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
            void openSettings() => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            void goBack() => Navigator.of(context).pop();
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

            // 滚动模式：无需分页计算
            if (settings.readingMode == ReadingMode.scroll) {
              return _ScrollView(
                key: ValueKey(
                  's-${state.book.id}-${state.currentChapterIndex}-${state.jumpToken}-${settings.fontSize.name}-${settings.lineHeight.name}',
                ),
                chapterText: state.currentChapterText,
                padding: _padding,
                textStyle: textStyle,
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
              );
            }

            // 翻页模式：仅此分支需要分页计算
            final contentWidth = constraints.maxWidth - _padding.horizontal;
            final contentHeight = constraints.maxHeight - _padding.vertical;
            final pagination = _paginate(
              text: state.currentChapterText,
              style: textStyle,
              contentWidth: contentWidth,
              contentHeight: contentHeight,
              chapterIndex: state.currentChapterIndex,
              fontSizeName: settings.fontSize.name,
              lineHeightName: settings.lineHeight.name,
            );
            return _PaginatedView(
              key: ValueKey(
                'p-${state.book.id}-${state.currentChapterIndex}-${state.jumpToken}-${settings.fontSize.name}-${settings.lineHeight.name}-${constraints.maxWidth.toInt()}x${constraints.maxHeight.toInt()}',
              ),
              pagination: pagination,
              padding: _padding,
              textStyle: textStyle,
              themeFg: settings.theme.foreground,
              chapterTitle: state.currentChapter.title,
              menuVisible: _menuVisible,
              chapterBookmarkOffsets: chapterBookmarkOffsets,
              initialPage: pagination.pageOfOffset(effectiveOffset),
              onPageChanged: (pageIndex) =>
                  reportOffset(pagination.offsetOfPage(pageIndex)),
              onTapCenter: tapCenter,
              onPrevChapter: onPrevChapter,
              onNextChapter: onNextChapter,
              onOpenChapters: openChapters,
              onOpenSettings: openSettings,
              onAddBookmark: (charOffset) =>
                  _addBookmark(state.currentChapterIndex, charOffset),
              onBack: goBack,
            );
          },
        ),
      ),
    );
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

class _PaginatedView extends StatefulWidget {
  final Pagination pagination;
  final EdgeInsets padding;
  final TextStyle textStyle;
  final Color themeFg;
  final String chapterTitle;
  final bool menuVisible;
  // 当前章节内所有书签的字符偏移；用于判断"当前页是否含书签"
  final Set<int> chapterBookmarkOffsets;
  final int initialPage;
  final void Function(int) onPageChanged;
  final VoidCallback onTapCenter;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;
  // 加书签：传入当前页起始的章节内偏移
  final void Function(int charOffset) onAddBookmark;
  final VoidCallback onBack;

  const _PaginatedView({
    super.key,
    required this.pagination,
    required this.padding,
    required this.textStyle,
    required this.themeFg,
    required this.chapterTitle,
    required this.menuVisible,
    required this.chapterBookmarkOffsets,
    required this.initialPage,
    required this.onPageChanged,
    required this.onTapCenter,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onOpenChapters,
    required this.onOpenSettings,
    required this.onAddBookmark,
    required this.onBack,
  });

  @override
  State<_PaginatedView> createState() => _PaginatedViewState();
}

class _PaginatedViewState extends State<_PaginatedView> {
  late final PageController _ctrl = PageController(
    initialPage: widget.initialPage,
  );
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _goPrev() {
    if (_currentPage > 0) {
      _ctrl.jumpToPage(_currentPage - 1);
    } else if (widget.onPrevChapter != null) {
      widget.onPrevChapter!();
    }
  }

  void _goNext() {
    if (_currentPage < widget.pagination.pageCount - 1) {
      _ctrl.jumpToPage(_currentPage + 1);
    } else if (widget.onNextChapter != null) {
      widget.onNextChapter!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      children: [
        // 文本页：PageView 切换，无动画
        PageView.builder(
          controller: _ctrl,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.pagination.pageCount,
          onPageChanged: (i) {
            setState(() => _currentPage = i);
            widget.onPageChanged(i);
          },
          itemBuilder: (_, i) => Padding(
            padding: widget.padding,
            child: Text(widget.pagination.pages[i], style: widget.textStyle),
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
                        onTap: _goPrev,
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
                        onTap: _goNext,
                      ),
                    ),
                  ],
                ),
        ),
        // 顶部章节标题（菜单可见时显示）
        if (widget.menuVisible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: widget.onBack,
                  ),
                  Expanded(
                    child: Text(
                      widget.chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 底部页码（始终显示，淡灰色不打扰）
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              '${_currentPage + 1} / ${widget.pagination.pageCount}',
              style: TextStyle(
                color: widget.themeFg.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ),
        ),
        // 右上角书签标记：仅当前页范围内含书签时显示
        // 菜单显示时让位给顶部栏，避免重叠
        if (!widget.menuVisible && _currentPageHasBookmark())
          Positioned(
            top: 8,
            right: 8,
            child: Icon(
              Icons.bookmark,
              size: 20,
              color: widget.themeFg.withValues(alpha: 0.6),
            ),
          ),
        // 底部菜单（菜单可见时显示）
        if (widget.menuVisible)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _menuButton(
                    Icons.skip_previous,
                    l10n.previousChapter,
                    onTap: widget.onPrevChapter,
                  ),
                  _menuButton(
                    Icons.skip_next,
                    l10n.nextChapter,
                    onTap: widget.onNextChapter,
                  ),
                  _menuButton(
                    Icons.list,
                    l10n.contentsAndBookmarks,
                    onTap: widget.onOpenChapters,
                  ),
                  _menuButton(
                    Icons.bookmark_add_outlined,
                    l10n.addBookmark,
                    onTap: () => widget.onAddBookmark(
                      widget.pagination.offsetOfPage(_currentPage),
                    ),
                  ),
                  _menuButton(
                    Icons.text_fields,
                    l10n.commonSettings,
                    onTap: widget.onOpenSettings,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // 当前页 [pageStart, pageEnd) 范围内是否有书签
  bool _currentPageHasBookmark() {
    if (widget.chapterBookmarkOffsets.isEmpty) return false;
    final pageStart = widget.pagination.offsetOfPage(_currentPage);
    final pageEnd = pageStart + widget.pagination.pages[_currentPage].length;
    for (final off in widget.chapterBookmarkOffsets) {
      if (off >= pageStart && off < pageEnd) return true;
    }
    return false;
  }

  Widget _menuButton(IconData icon, String label, {VoidCallback? onTap}) {
    final disabled = onTap == null;
    final color = disabled ? Colors.grey : Colors.white;
    // 等宽分配 + 图标在上文字在下：窄屏（手机）下 5 个按钮也能完整显示
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 滚动阅读视图 ────────────────────────────────────────────────

class _ScrollView extends StatefulWidget {
  final String chapterText;
  final EdgeInsets padding;
  final TextStyle textStyle;
  final Color themeFg;
  final String chapterTitle;
  final bool menuVisible;
  final int initialCharOffset;
  final void Function(int) onCharOffsetChanged;
  final VoidCallback onTapCenter;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onOpenChapters;
  final VoidCallback onOpenSettings;
  final void Function(int charOffset) onAddBookmark;
  final VoidCallback onBack;

  const _ScrollView({
    super.key,
    required this.chapterText,
    required this.padding,
    required this.textStyle,
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
  });

  @override
  State<_ScrollView> createState() => _ScrollViewState();
}

class _ScrollViewState extends State<_ScrollView> {
  late final ScrollController _ctrl;
  // 阅读进度百分比：用 ValueNotifier 单独驱动底部百分比刷新，
  // 避免滚动时 setState 重建整个视图（含大段正文 Text）
  final ValueNotifier<double> _progress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController();
    _ctrl.addListener(_onScroll);
    // 首帧渲染完成后按字符偏移比例滚动到初始位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctrl.hasClients) return;
      final max = _ctrl.position.maxScrollExtent;
      if (max > 0 && widget.chapterText.isNotEmpty) {
        final ratio = widget.initialCharOffset / widget.chapterText.length;
        _ctrl.jumpTo((ratio * max).clamp(0.0, max));
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final max = _ctrl.position.maxScrollExtent;
    if (max <= 0) return;
    final p = (_ctrl.offset / max).clamp(0.0, 1.0);
    if ((p - _progress.value).abs() > 0.001) _progress.value = p;
  }

  int get _currentCharOffset {
    if (!_ctrl.hasClients) return widget.initialCharOffset;
    final max = _ctrl.position.maxScrollExtent;
    if (max <= 0) return 0;
    final ratio = (_ctrl.offset / max).clamp(0.0, 1.0);
    return (ratio * widget.chapterText.length).round();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      children: [
        // 连续滚动文本；停止滚动时保存进度
        NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            widget.onCharOffsetChanged(_currentCharOffset);
            return false;
          },
          child: SingleChildScrollView(
            controller: _ctrl,
            padding: widget.padding,
            child: Text(widget.chapterText, style: widget.textStyle),
          ),
        ),
        // 透明手势层：点击任意处切换菜单
        // translucent 让下层滚动手势仍能响应（点击=切菜单，拖动=滚动）
        // 放在顶/底栏之前 → 顶/底栏 z 序更高，按钮点击优先命中
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTapCenter,
          ),
        ),
        // 顶部章节标题（菜单可见时显示）
        if (widget.menuVisible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: widget.onBack,
                  ),
                  Expanded(
                    child: Text(
                      widget.chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
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
        // 底部菜单（菜单可见时显示）
        if (widget.menuVisible)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _menuBtn(
                    Icons.skip_previous,
                    l10n.previousChapter,
                    onTap: widget.onPrevChapter,
                  ),
                  _menuBtn(
                    Icons.skip_next,
                    l10n.nextChapter,
                    onTap: widget.onNextChapter,
                  ),
                  _menuBtn(
                    Icons.list,
                    l10n.contentsAndBookmarks,
                    onTap: widget.onOpenChapters,
                  ),
                  _menuBtn(
                    Icons.bookmark_add_outlined,
                    l10n.addBookmark,
                    onTap: () => widget.onAddBookmark(_currentCharOffset),
                  ),
                  _menuBtn(
                    Icons.text_fields,
                    l10n.commonSettings,
                    onTap: widget.onOpenSettings,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _menuBtn(IconData icon, String label, {VoidCallback? onTap}) {
    final disabled = onTap == null;
    final color = disabled ? Colors.grey : Colors.white;
    // 等宽分配 + 图标在上文字在下：窄屏（手机）下 5 个按钮也能完整显示
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
