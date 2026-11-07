// 导入告警：有损解码不阻断阅读，但必须明确提示用户核对正文，且可手动关闭。
import 'package:flutter/material.dart';

import '../../shared/l10n/app_l10n.dart';
import '../../shared/theme/app_tokens.dart';

class ImportWarningsNotice extends StatelessWidget {
  final List<String> bookTitles;
  final VoidCallback onDismiss;

  const ImportWarningsNotice({
    super.key,
    required this.bookTitles,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (bookTitles.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Icon(
                Icons.warning_amber_outlined,
                color: colors.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ConstrainedBox(
                // 批量导入可能产生很多告警，限制提示区高度以免挤掉书架和操作入口。
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * 0.25).clamp(
                    0.0,
                    160.0,
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    context.l10n.importDecodingWarning(bookTitles.join('\n')),
                    style: TextStyle(color: colors.onTertiaryContainer),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onDismiss,
              icon: Icon(Icons.close, color: colors.onTertiaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
