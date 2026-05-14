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
    return Scaffold(
      appBar: AppBar(
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
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载书架失败：$e')),
        data: (state) => _Body(state: state),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('导入 txt'),
        onPressed: () => ref.read(libraryProvider.notifier).pickAndImport(),
      ),
    );
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
            itemBuilder: (context, i) => _BookTile(book: state.books[i]),
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
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(state.error!)),
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
          const Text('书架为空，点击下方按钮导入 txt 文件'),
        ],
      ),
    );
  }
}

class _BookTile extends ConsumerWidget {
  final Book book;
  const _BookTile({required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.menu_book, size: 32),
      title: Text(
        book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_formatChars(book.totalChars)}  ·  '
        '${book.lastReadAt == null ? "未读" : "上次阅读 ${_formatTime(book.lastReadAt!)}"}',
      ),
      trailing: PopupMenuButton<String>(
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
        onSelected: (v) async {
          if (v == 'delete') {
            final confirmed = await _confirmDelete(context, book.title);
            if (confirmed && context.mounted) {
              await ref.read(libraryProvider.notifier).deleteBook(book);
            }
          }
        },
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReaderPage(bookId: book.id)),
      ),
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
