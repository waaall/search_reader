import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/bookmark.dart';
import '../../../domain/chapter.dart';
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
              const TabBar(
                tabs: [
                  Tab(text: '目录'),
                  Tab(text: '书签'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ChaptersTab(
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

class _ChaptersTab extends StatelessWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final void Function(int chapterIndex) onJump;

  const _ChaptersTab({
    required this.chapters,
    required this.currentIndex,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: chapters.length,
      itemBuilder: (_, i) {
        final c = chapters[i];
        final isCurrent = i == currentIndex;
        return ListTile(
          dense: true,
          title: Text(
            c.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  isCurrent ? Theme.of(context).colorScheme.primary : null,
              fontWeight: isCurrent ? FontWeight.bold : null,
            ),
          ),
          onTap: () {
            Navigator.of(context).pop();
            onJump(i);
          },
        );
      },
    );
  }
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
      error: (e, _) => Center(child: Text('加载书签失败：$e')),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '还没有书签\n阅读时点底部「书签」按钮可添加',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: bookmarks.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) => _BookmarkTile(
            bookmark: bookmarks[i],
            chapterTitle: _chapterTitleOf(bookmarks[i].chapterIndex),
            onTap: () {
              Navigator.of(context).pop();
              onJump(bookmarks[i].chapterIndex, bookmarks[i].charOffset);
            },
            onDelete: () =>
                ref.read(bookmarksProvider(bookId).notifier).remove(bookmarks[i].id),
          ),
        );
      },
    );
  }

  // 通过 chapterIndex 查标题；越界（理论上不会）时给个兜底
  String _chapterTitleOf(int idx) {
    if (idx < 0 || idx >= chapters.length) return '未知章节';
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
      title: Text(
        chapterTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: note != null && note.isNotEmpty
          ? Text(note, maxLines: 2, overflow: TextOverflow.ellipsis)
          : Text(
              _formatTime(bookmark.createdAt),
              style: const TextStyle(color: Colors.grey),
            ),
      trailing: IconButton(
        tooltip: '删除',
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('删除书签'),
              content: const Text('确定删除这条书签？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除')),
              ],
            ),
          );
          if (confirmed == true) onDelete();
        },
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
