import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reader_settings.dart';
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
        body: Center(child: Text('打开失败：$e')),
      ),
      data: (state) => asyncSettings.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('设置加载失败：$e'))),
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
        ref.read(readerProvider(widget.bookId).notifier).jumpToChapter(
              ic,
              charOffset: widget.initialCharOffset ?? 0,
            );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final settings = widget.settings;
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
            // 分页：每次 build 重新计算（章节切换或字号改变都会触发）
            final contentWidth = constraints.maxWidth - _padding.horizontal;
            final contentHeight = constraints.maxHeight - _padding.vertical;
            final pagination = TextPaginator.paginate(
              text: state.currentChapterText,
              style: textStyle,
              contentWidth: contentWidth,
              contentHeight: contentHeight,
            );
            return _PaginatedView(
              key: ValueKey(
                  'p-${state.book.id}-${state.currentChapterIndex}-${settings.fontSize.name}-${settings.lineHeight.name}-${constraints.maxWidth.toInt()}x${constraints.maxHeight.toInt()}'),
              pagination: pagination,
              padding: _padding,
              textStyle: textStyle,
              themeFg: settings.theme.foreground,
              chapterTitle: state.currentChapter.title,
              menuVisible: _menuVisible,
              chapterBookmarkOffsets: chapterBookmarkOffsets,
              initialPage: pagination
                  .pageOfOffset(state.initialCharOffset),
              onPageChanged: (pageIndex) {
                final offset = pagination.offsetOfPage(pageIndex);
                ref
                    .read(readerProvider(widget.bookId).notifier)
                    .saveProgress(offset);
              },
              onTapCenter: () =>
                  setState(() => _menuVisible = !_menuVisible),
              onPrevChapter: state.hasPrev
                  ? () => ref
                      .read(readerProvider(widget.bookId).notifier)
                      .prevChapter()
                  : null,
              onNextChapter: state.hasNext
                  ? () => ref
                      .read(readerProvider(widget.bookId).notifier)
                      .nextChapter()
                  : null,
              onOpenChapters: () => Scaffold.of(context).openDrawer(),
              onOpenSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage())),
              onAddBookmark: (charOffset) =>
                  _addBookmark(state.currentChapterIndex, charOffset),
              onBack: () => Navigator.of(context).pop(),
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
    await ref.read(bookmarksProvider(widget.bookId).notifier).add(
          chapterIndex: chapterIndex,
          charOffset: charOffset,
          note: note.isEmpty ? null : note,
        );
    if (mounted) {
      setState(() => _menuVisible = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('书签已添加'), duration: Duration(seconds: 1)),
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
      title: const Text('添加书签'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(
          hintText: '备注（可留空）',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('取消')),
        TextButton(
            onPressed: () =>
                Navigator.pop(context, _controller.text.trim()),
            child: const Text('保存')),
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
  late final PageController _ctrl =
      PageController(initialPage: widget.initialPage);
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
            child: Text(
              widget.pagination.pages[i],
              style: widget.textStyle,
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
                  _menuButton(Icons.skip_previous, '上一章',
                      onTap: widget.onPrevChapter),
                  _menuButton(Icons.skip_next, '下一章',
                      onTap: widget.onNextChapter),
                  _menuButton(Icons.list, '目录和书签',
                      onTap: widget.onOpenChapters),
                  _menuButton(Icons.bookmark_add_outlined, '添加书签',
                      onTap: () => widget.onAddBookmark(
                          widget.pagination.offsetOfPage(_currentPage))),
                  _menuButton(Icons.text_fields, '设置',
                      onTap: widget.onOpenSettings),
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
    final pageEnd =
        pageStart + widget.pagination.pages[_currentPage].length;
    for (final off in widget.chapterBookmarkOffsets) {
      if (off >= pageStart && off < pageEnd) return true;
    }
    return false;
  }

  Widget _menuButton(IconData icon, String label, {VoidCallback? onTap}) {
    final disabled = onTap == null;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon,
          color: disabled ? Colors.grey : Colors.white, size: 20),
      label: Text(label,
          style: TextStyle(color: disabled ? Colors.grey : Colors.white)),
    );
  }
}
