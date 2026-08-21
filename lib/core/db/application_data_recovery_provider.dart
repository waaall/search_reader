// 应用数据恢复状态：把耗时恢复放到首帧之后执行，并向界面暴露进度和可重试错误。
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application_data_recovery.dart';
import 'database.dart';

enum ApplicationDataRecoveryStatus {
  idle,
  running,
  completed,
  completedWithIssues,
  failed,
}

class ApplicationDataRecoveryState {
  final ApplicationDataRecoveryStatus status;
  final ApplicationDataRecoveryProgress? progress;
  final ApplicationDataRecoveryReport? report;
  final Object? error;

  const ApplicationDataRecoveryState({
    required this.status,
    this.progress,
    this.report,
    this.error,
  });

  bool get isRunning => status == ApplicationDataRecoveryStatus.running;

  bool get searchMayBeIncomplete => report?.searchMayBeIncomplete ?? false;

  int get failedChapterCount => report?.failedChapterCount ?? 0;
}

class ApplicationDataRecoveryNotifier
    extends Notifier<ApplicationDataRecoveryState> {
  @override
  ApplicationDataRecoveryState build() => const ApplicationDataRecoveryState(
    status: ApplicationDataRecoveryStatus.idle,
  );

  // 首次启动和用户点击重试都走同一条路径；同一时间只允许一个恢复任务运行。
  Future<void> recover() async {
    if (state.isRunning) return;

    state = const ApplicationDataRecoveryState(
      status: ApplicationDataRecoveryStatus.running,
    );
    ApplicationDataRecoveryPhase? lastPhase;
    var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);

    void publishProgress(ApplicationDataRecoveryProgress progress) {
      final now = DateTime.now();
      final phaseChanged = progress.phase != lastPhase;
      final completed = progress.completed >= progress.total;
      final shouldPublish =
          phaseChanged ||
          completed ||
          now.difference(lastProgressAt) >= const Duration(milliseconds: 120);
      if (!shouldPublish) return;

      lastPhase = progress.phase;
      lastProgressAt = now;
      state = ApplicationDataRecoveryState(
        status: ApplicationDataRecoveryStatus.running,
        progress: progress,
      );
    }

    try {
      final report = await recoverApplicationData(
        AppDatabase.instance.db,
        onProgress: publishProgress,
      );
      state = ApplicationDataRecoveryState(
        status: report.hasIssues
            ? ApplicationDataRecoveryStatus.completedWithIssues
            : ApplicationDataRecoveryStatus.completed,
        report: report,
      );
    } catch (e, st) {
      // 恢复失败不会再阻塞应用首帧；保留错误并提供界面重试入口。
      debugPrint('应用数据后台恢复失败: $e\n$st');
      state = ApplicationDataRecoveryState(
        status: ApplicationDataRecoveryStatus.failed,
        error: e,
      );
    }
  }
}

final applicationDataRecoveryProvider =
    NotifierProvider<
      ApplicationDataRecoveryNotifier,
      ApplicationDataRecoveryState
    >(ApplicationDataRecoveryNotifier.new);
