import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/application_data_recovery_provider.dart';
import '../../domain/book.dart';
import '../../shared/l10n/app_formatters.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/app_tokens.dart';
import '../../shared/widgets/app_animated_switcher.dart';
import '../bookmarks/all_bookmarks_page.dart';
import '../reader/reader_page.dart';
import '../recovery/application_data_recovery_notice.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import 'library_provider.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 恢复可能发布新书、删除坏书或清理未完成导入；完成后重新读取书架。
    ref.listen(applicationDataRecoveryProvider, (previous, next) {
      if (previous?.isRunning == true && !next.isRunning) {
        ref.invalidate(libraryProvider);
      }
    });
    final recoveryRunning = ref
        .watch(applicationDataRecoveryProvider)
        .isRunning;
    final asyncState = ref.watch(libraryProvider);
    // 用 maybeWhen 取出当前状态，只为决定 AppBar / FAB / 返回键行为
    final state = asyncState.value;
    final selectionMode = state?.selectionMode ?? false;
    final selectedCount = state?.selectedIds.length ?? 0;
    final hasBooks = state?.books.isNotEmpty ?? false;

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
            ? _SelectionAppBar(
                selectedCount: selectedCount,
                recoveryRunning: recoveryRunning,
              )
            : _NormalAppBar(),
        body: Column(
          children: [
            const ApplicationDataRecoveryNotice(),
            Expanded(
              child: AppAnimatedSwitcher(
                child: asyncState.when(
                  loading: () => const Center(
                    key: ValueKey('library-loading'),
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, _) => Center(
                    key: const ValueKey('library-error'),
                    child: Text(context.l10n.loadLibraryFailed(e)),
                  ),
                  data: (state) => _Body(
                    key: const ValueKey('library-content'),
                    state: state,
                    recoveryRunning: recoveryRunning,
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: AnimatedSwitcher(
          duration: AppMotion.fast,
          switchInCurve: AppMotion.easeOut,
          switchOutCurve: AppMotion.easeInOut,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: selectionMode || !hasBooks
              ? const SizedBox.shrink(key: ValueKey('import-fab-hidden'))
              : FloatingActionButton.extended(
                  key: const ValueKey('import-fab'),
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.importBooks),
                  onPressed: recoveryRunning
                      ? null
                      : () =>
                            ref.read(libraryProvider.notifier).pickAndImport(),
                ),
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
          onPressed: () =>
              Navigator.of(context).push(appRoute((_) => const SearchPage())),
        ),
        IconButton(
          tooltip: context.l10n.bookmarksTitle,
          icon: const Icon(Icons.bookmark_outline),
          onPressed: () => Navigator.of(
            context,
          ).push(appRoute((_) => const AllBookmarksPage())),
        ),
        IconButton(
          tooltip: context.l10n.commonSettings,
          icon: const Icon(Icons.settings),
          onPressed: () =>
              Navigator.of(context).push(appRoute((_) => const SettingsPage())),
        ),
      ],
    );
  }
}

// 多选模式 AppBar：取消 / 已选数量 / 全选 / 删除
class _SelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final int selectedCount;
  final bool recoveryRunning;

  const _SelectionAppBar({
    required this.selectedCount,
    required this.recoveryRunning,
  });

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
          onPressed: selectedCount == 0 || recoveryRunning
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
  final bool recoveryRunning;

  const _Body({super.key, required this.state, required this.recoveryRunning});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        if (state.books.isEmpty && state.importing == null)
          _EmptyHint(
            onImport: recoveryRunning
                ? null
                : () => ref.read(libraryProvider.notifier).pickAndImport(),
          )
        else
          ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              96,
            ),
            itemCount: state.books.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final book = state.books[i];
              return _BookTile(
                    book: book,
                    progress: state.progressByBookId[book.id]?.fraction ?? 0,
                    selectionMode: state.selectionMode,
                    selected: state.selectedIds.contains(book.id),
                    recoveryRunning: recoveryRunning,
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
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
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
  final VoidCallback? onImport;

  const _EmptyHint({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child:
          Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.l10n.emptyLibraryHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: onImport,
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.importFirstBook),
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: AppMotion.normal)
              .slideY(begin: 0.1, end: 0, duration: AppMotion.normal),
    );
  }
}

class _BookTile extends ConsumerWidget {
  final Book book;
  final double progress;
  final bool selectionMode;
  final bool selected;
  final bool recoveryRunning;

  const _BookTile({
    required this.book,
    required this.progress,
    required this.selectionMode,
    required this.selected,
    required this.recoveryRunning,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(libraryProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.72)
        : colorScheme.surface;
    final borderColor = selected
        ? colorScheme.primary.withValues(alpha: 0.5)
        : colorScheme.outlineVariant;
    final progressValue = progress.clamp(0.0, 1.0);
    final progressLabel = AppFormatters.readingProgress(context, progressValue);
    final lastReadLabel = book.lastReadAt == null
        ? context.l10n.unread
        : context.l10n.lastReadAt(
            AppFormatters.relativeTime(context, book.lastReadAt!),
          );

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.easeOut,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: borderColor),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              if (selectionMode) {
                notifier.toggleSelect(book.id);
              } else {
                await Navigator.of(
                  context,
                ).push(appRoute((_) => ReaderPage(bookId: book.id)));
                // 阅读页返回后再刷新书架，确保最新进度和最后阅读时间立即可见。
                if (context.mounted) {
                  ref.invalidate(libraryProvider);
                }
              }
            },
            // 长按进入多选模式（普通模式下）；已在多选模式则忽略
            onLongPress: selectionMode
                ? null
                : () => notifier.enterSelection(book.id),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 多选模式下用 Checkbox 替代图标，直观显示选中态。
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: AppMotion.fast,
                        switchInCurve: AppMotion.easeOut,
                        switchOutCurve: AppMotion.easeInOut,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        ),
                        child: selectionMode
                            ? Checkbox(
                                key: const ValueKey('book-checkbox'),
                                value: selected,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (_) =>
                                    notifier.toggleSelect(book.id),
                              )
                            : DecoratedBox(
                                key: const ValueKey('book-icon'),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant,
                                  ),
                                ),
                                child: SizedBox.expand(
                                  child: Icon(
                                    Icons.menu_book_outlined,
                                    color: colorScheme.primary,
                                    size: 24,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: AppSpacing.sm + 2),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: progressValue,
                                minHeight: 5,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                color: colorScheme.primary,
                                backgroundColor:
                                    colorScheme.surfaceContainerHigh,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 44,
                              child: Text(
                                progressLabel,
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '$lastReadLabel  ·  '
                          '${AppFormatters.characterCount(context, book.totalChars)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (!selectionMode)
                    PopupMenuButton<String>(
                      tooltip: context.l10n.commonDetails,
                      enabled: !recoveryRunning,
                      padding: EdgeInsets.zero,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(context.l10n.commonDelete),
                        ),
                      ],
                      onSelected: (v) async {
                        if (v == 'delete') {
                          final confirmed = await _confirmDelete(
                            context,
                            book.title,
                          );
                          if (confirmed && context.mounted) {
                            await notifier.deleteBook(book);
                          }
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
