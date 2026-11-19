// 在书架内展示真实处理数，完成摘要与刷新错误分别呈现。
import 'package:flutter/material.dart';

import '../../../shared/l10n/app_formatters.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../library_batch.dart';
import '../library_provider.dart';

class LibraryBatchNotice extends StatelessWidget {
  final LibraryState state;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;
  const LibraryBatchNotice({
    super.key,
    required this.state,
    required this.onDismiss,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final batch = state.batch;
    final l10n = context.l10n;
    final importing = batch?.kind == LibraryBatchKind.importing;
    return Column(
      children: [
        if (batch != null &&
            state.busy &&
            (batch.processed < batch.total || state.currentName.isNotEmpty))
          ListTile(
            title: Text(
              importing
                  ? l10n.batchImportProgress(batch.processed, batch.total)
                  : l10n.batchDeleteProgress(batch.processed, batch.total),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batch.processed == batch.total
                      ? l10n.batchRefreshing
                      : [
                          if (state.importing != null)
                            AppFormatters.importPhase(
                              context,
                              state.importing!,
                            ),
                          state.currentName,
                        ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                LinearProgressIndicator(value: batch.processed / batch.total),
              ],
            ),
          )
        else if (batch != null)
          ListTile(
            title: Text(
              importing
                  ? l10n.batchImportResult(
                      batch.succeeded,
                      batch.skipped,
                      batch.failed,
                    )
                  : l10n.batchDeleteResult(batch.succeeded, batch.failed),
            ),
            subtitle: batch.importIssues.isEmpty
                ? null
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => _showIssues(context, batch),
                      child: Text(l10n.commonDetails),
                    ),
                  ),
            trailing: IconButton(
              onPressed: state.busy ? null : onDismiss,
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            ),
          ),
        if (state.refreshFailed)
          ListTile(
            title: Text(l10n.batchRefreshFailed),
            trailing: TextButton(
              onPressed: onRetry,
              child: Text(l10n.commonRetry),
            ),
          ),
      ],
    );
  }

  // 明细独立滚动，长批次不会把书架内容挤出屏幕。
  void _showIssues(BuildContext context, LibraryBatch batch) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.commonDetails),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: batch.importIssues.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(
                AppFormatters.libraryError(context, batch.importIssues[index]),
              ),
            ),
          ),
        ),
        actions: [CloseButton(onPressed: () => Navigator.pop(context))],
      ),
    );
  }
}
