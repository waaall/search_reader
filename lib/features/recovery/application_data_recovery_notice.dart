// 恢复状态提示：恢复任务不阻塞页面，但把搜索索引是否完整、是否可重试明确告诉用户。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/application_data_recovery.dart';
import '../../core/db/application_data_recovery_provider.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/theme/app_tokens.dart';

class ApplicationDataRecoveryNotice extends ConsumerWidget {
  const ApplicationDataRecoveryNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(applicationDataRecoveryProvider);
    final message = _message(context, state);
    if (message == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isRunning = state.isRunning;
    final colorScheme = theme.colorScheme;
    final background = isRunning
        ? colorScheme.secondaryContainer
        : colorScheme.errorContainer;
    final foreground = isRunning
        ? colorScheme.onSecondaryContainer
        : colorScheme.onErrorContainer;

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isRunning ? Icons.sync : Icons.warning_amber_outlined,
                color: foreground,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: TextStyle(color: foreground)),
                  if (isRunning && state.progress?.fraction != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    LinearProgressIndicator(
                      value: state.progress!.fraction,
                      color: foreground,
                      backgroundColor: foreground.withValues(alpha: 0.18),
                    ),
                  ],
                ],
              ),
            ),
            if (!isRunning) ...[
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: () => unawaited(
                  ref.read(applicationDataRecoveryProvider.notifier).recover(),
                ),
                child: Text(context.l10n.commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _message(BuildContext context, ApplicationDataRecoveryState state) {
    switch (state.status) {
      case ApplicationDataRecoveryStatus.idle:
      case ApplicationDataRecoveryStatus.completed:
        return null;
      case ApplicationDataRecoveryStatus.running:
        final progress = state.progress;
        if (progress?.phase ==
                ApplicationDataRecoveryPhase.rebuildingSearchIndex &&
            progress != null &&
            progress.total > 0) {
          return context.l10n.recoverySearchIndexProgress(
            progress.completed,
            progress.total,
          );
        }
        return context.l10n.recoveryInProgress;
      case ApplicationDataRecoveryStatus.completedWithIssues:
        final failedChapters = state.failedChapterCount;
        if (state.searchMayBeIncomplete && failedChapters > 0) {
          return context.l10n.recoverySearchIncomplete(failedChapters);
        }
        if (state.searchMayBeIncomplete) {
          return context.l10n.recoverySearchMayBeIncomplete;
        }
        return context.l10n.recoveryIncomplete;
      case ApplicationDataRecoveryStatus.failed:
        return context.l10n.recoveryFailed;
    }
  }
}
