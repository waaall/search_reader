import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../shared/l10n/app_formatters.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/app_tokens.dart';
import '../../shared/widgets/app_animated_switcher.dart';
import '../reader/reader_page.dart';
import 'all_bookmarks_provider.dart';

class AllBookmarksPage extends ConsumerWidget {
  const AllBookmarksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(allBookmarksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.bookmarksTitle)),
      body: AppAnimatedSwitcher(
        child: asyncList.when(
          loading: () => const Center(
            key: ValueKey('bookmarks-loading'),
            child: CircularProgressIndicator(),
          ),
          error: (e, _) => Center(
            key: const ValueKey('bookmarks-error'),
            child: Text(context.l10n.loadFailed(e)),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const _EmptyHint(key: ValueKey('bookmarks-empty'));
            }
            // 把 list 按 bookId 分组保留服务端排序，组内顺序即章节顺序
            final groups = _groupByBook(list);
            // 用 ListView.builder + 自维护索引展平：每组先插入 header，再插各 item
            // 用一个统一的 _Row 序列简化渲染
            final rows = _flatten(groups);
            return ListView.separated(
              key: ValueKey('bookmarks-list-${rows.length}'),
              itemCount: rows.length,
              separatorBuilder: (_, i) {
                final r = rows[i];
                return r is _BookmarkRow
                    ? const Divider(height: 1)
                    : const SizedBox.shrink();
              },
              itemBuilder: (_, i) {
                final r = rows[i];
                if (r is _BookHeaderRow) {
                  return _BookHeader(title: r.title)
                      .animate(delay: (i < 8 ? 20 * i : 0).ms)
                      .fadeIn(duration: AppMotion.fast)
                      .slideY(begin: 0.04, end: 0, duration: AppMotion.fast);
                }
                if (r is _BookmarkRow) {
                  return _BookmarkTile(
                        item: r.item,
                        onTap: () => Navigator.of(context).push(
                          appRoute(
                            (_) => ReaderPage(
                              bookId: r.item.bookmark.bookId,
                              initialChapterIndex: r.item.bookmark.chapterIndex,
                              initialCharOffset: r.item.bookmark.charOffset,
                            ),
                          ),
                        ),
                        onDelete: () => ref
                            .read(allBookmarksProvider.notifier)
                            .remove(r.item),
                      )
                      .animate(delay: (i < 8 ? 20 * i : 0).ms)
                      .fadeIn(duration: AppMotion.fast)
                      .slideY(begin: 0.04, end: 0, duration: AppMotion.fast);
                }
                return const SizedBox.shrink();
              },
            );
          },
        ),
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
    final createdAt = AppFormatters.relativeTime(
      context,
      item.bookmark.createdAt,
    );
    final chapterTitle = item.chapterTitle.isEmpty
        ? context.l10n.unknownChapter
        : item.chapterTitle;
    return ListTile(
      title: Text(chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: note != null && note.isNotEmpty
          ? Text(
              '$note  ·  $createdAt',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : Text(createdAt, style: const TextStyle(color: Colors.grey)),
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child:
          Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 96,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    context.l10n.emptyBookmarksHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              )
              .animate()
              .fadeIn(duration: AppMotion.normal)
              .slideY(begin: 0.1, end: 0, duration: AppMotion.normal),
    );
  }
}
