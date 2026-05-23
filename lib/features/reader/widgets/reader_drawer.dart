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
              color: isCurrent ? Theme.of(context).colorScheme.primary : null,
              fontWeight: isCurrent ? FontWeight.bold : null,
            ),
          ),
          onTap: () {
            // 只关闭抽屉，不走页面 Navigator.pop，避免触发阅读页退出逻辑
            Scaffold.of(context).closeDrawer();
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
