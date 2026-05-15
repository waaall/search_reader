import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../reader/reader_page.dart';
import 'all_bookmarks_provider.dart';

class AllBookmarksPage extends ConsumerWidget {
  const AllBookmarksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(allBookmarksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('书签')),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (list) {
          if (list.isEmpty) {
            return const _EmptyHint();
          }
          // 把 list 按 bookId 分组保留服务端排序，组内顺序即章节顺序
          final groups = _groupByBook(list);
          // 用 ListView.builder + 自维护索引展平：每组先插入 header，再插各 item
          // 用一个统一的 _Row 序列简化渲染
          final rows = _flatten(groups);
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, i) {
              final r = rows[i];
              return r is _BookmarkRow ? const Divider(height: 1) : const SizedBox.shrink();
            },
            itemBuilder: (_, i) {
              final r = rows[i];
              if (r is _BookHeaderRow) return _BookHeader(title: r.title);
              if (r is _BookmarkRow) {
                return _BookmarkTile(
                  item: r.item,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReaderPage(
                        bookId: r.item.bookmark.bookId,
                        initialChapterIndex: r.item.bookmark.chapterIndex,
                        initialCharOffset: r.item.bookmark.charOffset,
                      ),
                    ),
                  ),
                  onDelete: () =>
                      ref.read(allBookmarksProvider.notifier).remove(r.item),
                );
              }
              return const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }

  // 把扁平 list 按 bookId 分组，保留原顺序
  Map<int, List<BookmarkWithMeta>> _groupByBook(List<BookmarkWithMeta> list) {
    final map = <int, List<BookmarkWithMeta>>{};
    for (final it in list) {
      map.putIfAbsent(it.bookmark.bookId, () => []).add(it);
    }
    return map;
  }

  // 把分组展平成 [Header, Item, Item, Header, Item, ...] 的渲染序列
  List<_Row> _flatten(Map<int, List<BookmarkWithMeta>> groups) {
    final out = <_Row>[];
    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      out.add(_BookHeaderRow(entry.value.first.bookTitle));
      for (final it in entry.value) {
        out.add(_BookmarkRow(it));
      }
    }
    return out;
  }
}

// --- 渲染序列项类型（简单 sealed-like）-------------------------------------

abstract class _Row {
  const _Row();
}

class _BookHeaderRow extends _Row {
  final String title;
  const _BookHeaderRow(this.title);
}

class _BookmarkRow extends _Row {
  final BookmarkWithMeta item;
  const _BookmarkRow(this.item);
}

// --- UI 组件 --------------------------------------------------------------

class _BookHeader extends StatelessWidget {
  final String title;
  const _BookHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      width: double.infinity,
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final BookmarkWithMeta item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookmarkTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final note = item.bookmark.note?.trim();
    return ListTile(
      title: Text(
        item.chapterTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: note != null && note.isNotEmpty
          ? Text('$note  ·  ${_formatTime(item.bookmark.createdAt)}',
              maxLines: 2, overflow: TextOverflow.ellipsis)
          : Text(
              _formatTime(item.bookmark.createdAt),
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border,
              size: 96, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('还没有书签\n阅读时点底部「书签」按钮可添加',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
