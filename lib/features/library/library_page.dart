import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/book.dart';
import '../reader/reader_page.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import 'library_provider.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(libraryProvider);
    // 用 maybeWhen 取出当前状态，只为决定 AppBar / FAB / 返回键行为
    final state = asyncState.value;
    final selectionMode = state?.selectionMode ?? false;
    final selectedCount = state?.selectedIds.length ?? 0;

    return PopScope(
      // 多选模式下：拦截系统返回键，先退出多选模式而不是关闭页面
      canPop: !selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selectionMode) {
          ref.read(libraryProvider.notifier).exitSelection();
        }
      },
      child: Scaffold(
        appBar: selectionMode
            ? _SelectionAppBar(selectedCount: selectedCount)
            : _NormalAppBar(),
        body: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载书架失败：$e')),
          data: (state) => _Body(state: state),
        ),
        floatingActionButton: selectionMode
            ? null
            : FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text('导入书籍'),
                onPressed: () =>
                    ref.read(libraryProvider.notifier).pickAndImport(),
              ),
      ),
    );
  }
}

// 普通模式 AppBar：搜索 + 设置
class _NormalAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('书架'),
      actions: [
        IconButton(
          tooltip: '搜索',
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchPage()),
          ),
        ),
        IconButton(
          tooltip: '设置',
          icon: const Icon(Icons.settings),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          ),
        ),
      ],
    );
  }
}

// 多选模式 AppBar：取消 / 已选数量 / 全选 / 删除
class _SelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final int selectedCount;
  const _SelectionAppBar({required this.selectedCount});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(libraryProvider.notifier);
    return AppBar(
      leading: IconButton(
        tooltip: '退出多选',
        icon: const Icon(Icons.close),
        onPressed: notifier.exitSelection,
      ),
      title: Text('已选 $selectedCount 本'),
      actions: [
        IconButton(
          tooltip: '全选',
          icon: const Icon(Icons.select_all),
          onPressed: notifier.selectAll,
        ),
        IconButton(
          tooltip: '删除',
          icon: const Icon(Icons.delete_outline),
          onPressed: selectedCount == 0
              ? null
              : () => _confirmAndDelete(context, ref, selectedCount),
        ),
      ],
    );
  }

  Future<void> _confirmAndDelete(
      BuildContext context, WidgetRef ref, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 $count 本书及其阅读进度？'),
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
    if (confirmed == true) {
      await ref.read(libraryProvider.notifier).deleteSelected();
    }
  }
}

class _Body extends ConsumerWidget {
  final LibraryState state;
  const _Body({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        if (state.books.isEmpty && state.importing == null)
          const _EmptyHint()
        else
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: state.books.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final book = state.books[i];
              return _BookTile(
                book: book,
                selectionMode: state.selectionMode,
                selected: state.selectedIds.contains(book.id),
              );
            },
          ),
        if (state.importing != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 90,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                leading: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text(state.importing!.label),
              ),
            ),
          ),
        if (state.error != null)
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Material(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 背景固定浅红 → 图标和文字都用深红，保证深/浅主题下对比度一致
                    Icon(Icons.error_outline, color: Colors.red.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
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
          Icon(Icons.menu_book_outlined,
              size: 96, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('书架为空，点击下方按钮导入 txt 或 epub 文件'),
        ],
      ),
    );
  }
}

class _BookTile extends ConsumerWidget {
  final Book book;
  final bool selectionMode;
  final bool selected;
  const _BookTile({
    required this.book,
    required this.selectionMode,
    required this.selected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(libraryProvider.notifier);
    return ListTile(
      // 多选模式下用 Checkbox 替代图标，直观显示选中态
      leading: selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => notifier.toggleSelect(book.id),
            )
          : const Icon(Icons.menu_book, size: 32),
      title: Text(
        book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_formatChars(book.totalChars)}  ·  '
        '${book.lastReadAt == null ? "未读" : "上次阅读 ${_formatTime(book.lastReadAt!)}"}',
      ),
      // 多选模式下隐藏单本菜单，避免操作冲突
      trailing: selectionMode
          ? null
          : PopupMenuButton<String>(
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
              onSelected: (v) async {
                if (v == 'delete') {
                  final confirmed = await _confirmDelete(context, book.title);
                  if (confirmed && context.mounted) {
                    await notifier.deleteBook(book);
                  }
                }
              },
            ),
      onTap: () {
        if (selectionMode) {
          notifier.toggleSelect(book.id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ReaderPage(bookId: book.id)),
          );
        }
      },
      // 长按进入多选模式（普通模式下）；已在多选模式则忽略
      onLongPress: selectionMode ? null : () => notifier.enterSelection(book.id),
      selected: selected,
    );
  }

  String _formatChars(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)} 万字';
    return '$n 字';
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

  Future<bool> _confirmDelete(BuildContext context, String title) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定删除《$title》及其阅读进度？'),
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
    return result ?? false;
  }
}
