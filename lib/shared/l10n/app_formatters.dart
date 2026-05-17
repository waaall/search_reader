import 'package:flutter/widgets.dart';

import '../../features/importer/import_progress.dart';
import '../../features/library/library_error.dart';
import 'app_l10n.dart';

// 本地化格式化工具：动态文案只在 UI 渲染时按当前语言生成，语言切换可立即刷新。
class AppFormatters {
  const AppFormatters._();

  static String relativeTime(BuildContext context, DateTime time) {
    final l10n = context.l10n;
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.hoursAgo(diff.inHours);
    if (diff.inDays < 30) return l10n.daysAgo(diff.inDays);
    return _formatDate(time);
  }

  static String characterCount(BuildContext context, int count) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'zh' && count >= 10000) {
      return l10n.characterCountTenThousand((count / 10000).toStringAsFixed(1));
    }
    return l10n.characterCount(count);
  }

  static String importPhase(BuildContext context, ImportPhase phase) {
    final l10n = context.l10n;
    return switch (phase) {
      ImportPhase.copying => l10n.importPhaseCopying,
      ImportPhase.parsing => l10n.importPhaseParsing,
      ImportPhase.indexing => l10n.importPhaseIndexing,
      ImportPhase.done => l10n.importPhaseDone,
    };
  }

  static String libraryError(BuildContext context, LibraryError error) {
    final l10n = context.l10n;
    return switch (error) {
      FileTooLargeError(:final fileName) => l10n.fileTooLarge(fileName),
      UnsupportedFilesError(:final fileNames) => l10n.unsupportedFileFormats(
        fileNames.join('\n'),
      ),
      ImportFailedError(:final exception) => l10n.importFailed(
        importException(context, exception),
      ),
      UnexpectedImportError(:final details) => l10n.importFailed(
        l10n.importDetailPrefix(details.toString()),
      ),
      PartialDeleteFailedError(:final failures) => l10n.partialDeleteFailed(
        failures.map((f) => '${f.title}: ${f.details}').join('\n'),
      ),
    };
  }

  static String importException(BuildContext context, ImportException error) {
    final l10n = context.l10n;
    return switch (error.kind) {
      ImportFailureKind.unsupportedFormat => l10n.importUnsupportedFormat(
        error.value ?? '',
      ),
      ImportFailureKind.decodingFailed => _withOptionalDetail(
        l10n.importCannotDecode,
        error.detail,
        (detail) => l10n.importDetailPrefix(detail),
      ),
      ImportFailureKind.unexpected => _withOptionalDetail(
        l10n.importUnexpectedFailure,
        error.detail,
        (detail) => l10n.importDetailPrefix(detail),
      ),
    };
  }

  static String _withOptionalDetail(
    String message,
    Object? detail,
    String Function(String detail) detailBuilder,
  ) {
    if (detail == null) return message;
    return '$message\n${detailBuilder(detail.toString())}';
  }

  static String _formatDate(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }
}
