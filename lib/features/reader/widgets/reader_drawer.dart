import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/bookmark.dart';
import '../../../domain/chapter.dart';
import '../../../shared/l10n/app_formatters.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../bookmark_provider.dart';

// 阅读器侧边抽屉：目录 + 书签 双 tab
// 跳转回调统一为 (chapterIndex, charOffset)：
//   - 章节列表跳转：charOffset = 0
//   - 书签跳转：charOffset = bookmark.charOffset
class ReaderDrawer extends ConsumerWidget {
  final int bookId;
  final List<Chapter> chapters;
  final int currentChapterIndex;
  final void Function(int chapterIndex, int charOffset) onJump;

  const ReaderDrawer({
    super.key,
    required this.bookId,
    required this.chapters,
    required this.currentChapterIndex,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: context.l10n.contentsTitle),
                  Tab(text: context.l10n.bookmarksTitle),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ChapterDirectory(
                      chapters: chapters,
                      currentIndex: currentChapterIndex,
                      onJump: (i) => onJump(i, 0),
                    ),
                    _BookmarksTab(
                      bookId: bookId,
                      chapters: chapters,
                      onJump: onJump,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChapterDirectory extends StatefulWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final void Function(int chapterIndex) onJump;
  final ScrollController? scrollController;

  const ChapterDirectory({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onJump,
    this.scrollController,
  });

  @override
  State<ChapterDirectory> createState() => _ChapterDirectoryState();
}

class _ChapterDirectoryState extends State<ChapterDirectory> {
  static const double _rowExtent = 48;

  final TextEditingController _queryController = TextEditingController();
  final Set<int> _expandedVolumeIds = {};
  late final ScrollController _scrollController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ensureCurrentVolumeExpanded();
    final rows = _visibleRows();
    final currentRow = _currentRowIndex(rows);
    final initialOffset = currentRow < 0
        ? 0.0
        : ((currentRow - 2).clamp(0, rows.length) * _rowExtent);
    _scrollController =
        widget.scrollController ??
        ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void didUpdateWidget(ChapterDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.chapters != widget.chapters) {
      _ensureCurrentVolumeExpanded();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    if (widget.scrollController == null) _scrollController.dispose();
    super.dispose();
  }

  void _ensureCurrentVolumeExpanded() {
    for (final group in _chapterGroups(widget.chapters)) {
      if (group.volumeId != null &&
          group.chapters.any(
            (chapter) => chapter.chapterIndex == widget.currentIndex,
          )) {
        _expandedVolumeIds.add(group.volumeId!);
      }
    }
  }

  void _scrollToCurrent() {
    if (!mounted || !_scrollController.hasClients || _query.isNotEmpty) return;
    final rows = _visibleRows();
    final index = _currentRowIndex(rows);
    if (index < 0) return;
    final position = _scrollController.position;
    final target = ((index - 2).clamp(0, rows.length) * _rowExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  int _currentRowIndex(List<_DirectoryRow> rows) => rows.indexWhere(
    (row) =>
        row is _ChapterRow && row.chapter.chapterIndex == widget.currentIndex,
  );

  List<_DirectoryRow> _visibleRows() {
    if (_query.isNotEmpty) {
      final normalized = _query.toLowerCase();
      return [
        for (final chapter in widget.chapters)
          if (chapter.title.toLowerCase().contains(normalized))
            _ChapterRow(chapter),
      ];
    }

    final groups = _chapterGroups(widget.chapters);
    final hasVolumes = groups.any((group) => group.volumeId != null);
    if (!hasVolumes) {
      return [for (final chapter in widget.chapters) _ChapterRow(chapter)];
    }

    final rows = <_DirectoryRow>[];
    for (final group in groups) {
      final volumeId = group.volumeId;
      if (volumeId == null) {
        rows.addAll(group.chapters.map(_ChapterRow.new));
        continue;
      }
      final expanded = _expandedVolumeIds.contains(volumeId);
      rows.add(
        _VolumeRow(
          volumeId: volumeId,
          title: group.title!,
          chapterCount: group.chapters.length,
          expanded: expanded,
        ),
      );
      if (expanded) rows.addAll(group.chapters.map(_ChapterRow.new));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.currentChapterPosition(
                    widget.currentIndex + 1,
                    widget.chapters.length,
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (_query.isNotEmpty)
                Text(
                  context.l10n.chapterSearchResultCount(rows.length),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            key: const ValueKey('chapter-search-field'),
            controller: _queryController,
            decoration: InputDecoration(
              hintText: context.l10n.chapterSearchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.l10n.commonClear,
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _queryController.clear();
                        setState(() => _query = '');
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _scrollToCurrent(),
                        );
                      },
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  key: const ValueKey('chapter-search-empty'),
                  child: Text(
                    context.l10n.noChapterSearchResults,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('chapter-directory-list'),
                  controller: _scrollController,
                  itemExtent: _rowExtent,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row is _VolumeRow) {
                      return ListTile(
                        key: ValueKey('volume-row-${row.volumeId}'),
                        dense: true,
                        leading: Icon(
                          row.expanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                        ),
                        title: Text(
                          row.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: Text(
                          context.l10n.chapterCount(row.chapterCount),
                        ),
                        onTap: () => setState(() {
                          if (row.expanded) {
                            _expandedVolumeIds.remove(row.volumeId);
                          } else {
                            _expandedVolumeIds.add(row.volumeId);
                          }
                        }),
                      );
                    }

                    final chapter = (row as _ChapterRow).chapter;
                    final isCurrent =
                        chapter.chapterIndex == widget.currentIndex;
                    return ListTile(
                      key: ValueKey('chapter-row-${chapter.chapterIndex}'),
                      dense: true,
                      selected: isCurrent,
                      title: Text(
                        chapter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight: isCurrent ? FontWeight.bold : null,
                        ),
                      ),
                      trailing: _query.isNotEmpty
                          ? Text('${chapter.chapterIndex + 1}')
                          : null,
                      onTap: () {
                        // 只关闭抽屉，不走页面 Navigator.pop，避免触发阅读页退出逻辑。
                        Scaffold.maybeOf(context)?.closeDrawer();
                        widget.onJump(chapter.chapterIndex);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

abstract class _DirectoryRow {
  const _DirectoryRow();
}

class _ChapterRow extends _DirectoryRow {
  final Chapter chapter;

  const _ChapterRow(this.chapter);
}

class _VolumeRow extends _DirectoryRow {
  final int volumeId;
  final String title;
  final int chapterCount;
  final bool expanded;

  const _VolumeRow({
    required this.volumeId,
    required this.title,
    required this.chapterCount,
    required this.expanded,
  });
}

class _ChapterGroup {
  final int? volumeId;
  final String? title;
  final List<Chapter> chapters;

  const _ChapterGroup({
    required this.volumeId,
    required this.title,
    required this.chapters,
  });
}

List<_ChapterGroup> _chapterGroups(List<Chapter> chapters) {
  final groups = <_ChapterGroup>[];
  int? currentVolumeId;
  String? currentTitle;
  var currentChapters = <Chapter>[];

  void flush() {
    if (currentChapters.isEmpty) return;
    groups.add(
      _ChapterGroup(
        volumeId: currentVolumeId,
        title: currentTitle,
        chapters: currentChapters,
      ),
    );
  }

  for (final chapter in chapters) {
    if (_isVolumeTitle(chapter.title)) {
      flush();
      currentVolumeId = chapter.chapterIndex;
      currentTitle = chapter.title;
      currentChapters = [chapter];
    } else {
      currentChapters.add(chapter);
    }
  }
  flush();
  return groups;
}

bool _isVolumeTitle(String title) {
  final trimmed = title.trim();
  return RegExp(r'^第\s*[零〇一二三四五六七八九十百千万两\d]+\s*[卷部]').hasMatch(trimmed) ||
      RegExp(r'^[卷部]\s*[零〇一二三四五六七八九十百千万两上下中前后终\d]+').hasMatch(trimmed) ||
      RegExp(r'^[上下中前后终]\s*[卷部](?:\s|$|[：:])').hasMatch(trimmed) ||
      RegExp(
        r'^(?:volume|vol\.?|book|part)\s+[\w\d]+',
        caseSensitive: false,
      ).hasMatch(trimmed);
}

class _BookmarksTab extends ConsumerWidget {
  final int bookId;
  final List<Chapter> chapters;
  final void Function(int chapterIndex, int charOffset) onJump;

  const _BookmarksTab({
    required this.bookId,
    required this.chapters,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncBookmarks = ref.watch(bookmarksProvider(bookId));
    return asyncBookmarks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(context.l10n.loadBookmarksFailed(e))),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.l10n.emptyBookmarksHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: bookmarks.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) => _BookmarkTile(
            bookmark: bookmarks[i],
            chapterTitle: _chapterTitleOf(context, bookmarks[i].chapterIndex),
            onTap: () {
              // 只关闭抽屉，不走页面 Navigator.pop，避免触发阅读页退出逻辑
              Scaffold.of(context).closeDrawer();
              onJump(bookmarks[i].chapterIndex, bookmarks[i].charOffset);
            },
            onDelete: () => ref
                .read(bookmarksProvider(bookId).notifier)
                .remove(bookmarks[i].id),
          ),
        );
      },
    );
  }

  // 通过 chapterIndex 查标题；越界（理论上不会）时给本地化兜底
  String _chapterTitleOf(BuildContext context, int idx) {
    if (idx < 0 || idx >= chapters.length) return context.l10n.unknownChapter;
    return chapters[idx].title;
  }
}

class _BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final String chapterTitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookmarkTile({
    required this.bookmark,
    required this.chapterTitle,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final note = bookmark.note?.trim();
    return ListTile(
      dense: true,
      title: Text(chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: note != null && note.isNotEmpty
          ? Text(note, maxLines: 2, overflow: TextOverflow.ellipsis)
          : Text(
              AppFormatters.relativeTime(context, bookmark.createdAt),
              style: const TextStyle(color: Colors.grey),
            ),
      trailing: IconButton(
        tooltip: context.l10n.commonDelete,
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(context.l10n.deleteBookmark),
              content: Text(context.l10n.confirmDeleteBookmark),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.commonCancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.commonDelete),
                ),
              ],
            ),
          );
          if (confirmed == true) onDelete();
        },
      ),
      onTap: onTap,
    );
  }
}
