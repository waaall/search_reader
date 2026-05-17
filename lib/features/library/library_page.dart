import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/book.dart';
import '../../shared/l10n/app_formatters.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/theme/app_tokens.dart';
import '../bookmarks/all_bookmarks_page.dart';
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
          error: (e, _) =>
              Center(child: Text(context.l10n.loadLibraryFailed(e))),
          data: (state) => _Body(state: state),
        ),
        floatingActionButton: selectionMode
            ? null
            : FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: Text(context.l10n.importBooks),
                onPressed: () =>
                    ref.read(libraryProvider.notifier).pickAndImport(),
              ),
      ),
    );
  }
}

// 普通模式 AppBar：搜索 + 书签 + 设置
class _NormalAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(context.l10n.libraryTitle),
      actions: [
        IconButton(
          tooltip: context.l10n.commonSearch,
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        ),
        IconButton(
          tooltip: context.l10n.bookmarksTitle,
          icon: const Icon(Icons.bookmark_outline),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AllBookmarksPage())),
        ),
        IconButton(
          tooltip: context.l10n.commonSettings,
          icon: const Icon(Icons.settings),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
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
        tooltip: context.l10n.exitSelection,
        icon: const Icon(Icons.close),
        onPressed: notifier.exitSelection,
      ),
      title: Text(context.l10n.selectedBooks(selectedCount)),
      actions: [
        IconButton(
          tooltip: context.l10n.selectAll,
          icon: const Icon(Icons.select_all),
          onPressed: notifier.selectAll,
        ),
        IconButton(
          tooltip: context.l10n.commonDelete,
          icon: const Icon(Icons.delete_outline),
          onPressed: selectedCount == 0
              ? null
              : () => _confirmAndDelete(context, ref, selectedCount),
        ),
      ],
    );
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.batchDelete),
        content: Text(context.l10n.confirmBatchDelete(count)),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              96,
            ),
            itemCount: state.books.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final book = state.books[i];
              return _BookTile(
                    book: book,
                    selectionMode: state.selectionMode,
                    selected: state.selectedIds.contains(book.id),
                  )
                  // 列表项依次淡入上滑；仅前若干项错峰，避免滚到远处时延迟过长
                  .animate(delay: (i < 8 ? 40 * i : 0).ms)
                  .fadeIn(duration: AppMotion.normal)
                  .slideY(
                    begin: 0.08,
                    end: 0,
                    duration: AppMotion.normal,
                    curve: Curves.easeOut,
                  );
            },
          ),
        if (state.importing != null)
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: 90,
            child:
                Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: ListTile(
                        leading: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text(
                          AppFormatters.importPhase(context, state.importing!),
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: AppMotion.fast)
                    .slideY(
                      begin: 0.5,
                      end: 0,
                      duration: AppMotion.fast,
                      curve: Curves.easeOut,
                    ),
          ),
        if (state.error != null)
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.md,
            child:
                Material(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // 背景固定浅红 → 图标和文字都用深红，保证深/浅主题下对比度一致
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade900,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                AppFormatters.libraryError(
                                  context,
                                  state.error!,
                                ),
                                style: TextStyle(color: Colors.red.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: AppMotion.fast)
                    .slideY(
                      begin: -0.5,
                      end: 0,
                      duration: AppMotion.fast,
                      curve: Curves.easeOut,
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
      child:
          Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 96,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(context.l10n.emptyLibraryHint),
                ],
              )
              .animate()
              .fadeIn(duration: AppMotion.normal)
              .slideY(begin: 0.1, end: 0, duration: AppMotion.normal),
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
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${AppFormatters.characterCount(context, book.totalChars)}  ·  '
        '${book.lastReadAt == null ? context.l10n.unread : context.l10n.lastReadAt(AppFormatters.relativeTime(context, book.lastReadAt!))}',
      ),
      // 多选模式下隐藏单本菜单，避免操作冲突
      trailing: selectionMode
          ? null
          : PopupMenuButton<String>(
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.l10n.commonDelete),
                ),
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
      onLongPress: selectionMode
          ? null
          : () => notifier.enterSelection(book.id),
      selected: selected,
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String title) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.deleteBook),
        content: Text(context.l10n.confirmDeleteBook(title)),
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
    return result ?? false;
  }
}
