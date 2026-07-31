// 阅读页快捷设置弹层：只提供字号、行距和阅读主题，修改后立即作用于正文。
// 完整设置页继续保留语言与阅读模式等选项，避免两个入口职责重叠。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/reader_settings.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../settings/reader_settings_labels.dart';
import '../../settings/settings_provider.dart';

Future<void> showReaderSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) => const ReaderSettingsSheet(),
  );
}

class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(readerSettingsProvider);
    return asyncSettings.when(
      loading: () => const _LoadingSheet(),
      error: (error, _) => _ErrorSheet(error: error),
      data: (settings) => _SettingsSheetContent(
        settings: settings,
        notifier: ref.read(readerSettingsProvider.notifier),
      ),
    );
  }
}

class _SettingsSheetContent extends StatelessWidget {
  final ReaderSettings settings;
  final ReaderSettingsNotifier notifier;

  const _SettingsSheetContent({required this.settings, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final background = settings.theme.background;
    final foreground = settings.theme.foreground;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Material(
          color: background,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
            side: BorderSide(color: foreground.withValues(alpha: 0.12)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.readingSettingsSection,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        color: foreground.withValues(alpha: 0.72),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SettingChoiceRow<FontSizeLevel>(
                    title: context.l10n.fontSizeSection,
                    values: FontSizeLevel.values,
                    selected: settings.fontSize,
                    labelOf: (value) => readerFontSizeLabel(context, value),
                    onChanged: notifier.updateFontSize,
                    background: background,
                    foreground: foreground,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SettingChoiceRow<LineHeightLevel>(
                    title: context.l10n.lineHeightSection,
                    values: LineHeightLevel.values,
                    selected: settings.lineHeight,
                    labelOf: (value) => readerLineHeightLabel(context, value),
                    onChanged: notifier.updateLineHeight,
                    background: background,
                    foreground: foreground,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SettingChoiceRow<ReaderThemeMode>(
                    title: context.l10n.readerThemeSection,
                    values: ReaderThemeMode.values,
                    selected: settings.theme,
                    labelOf: (value) => readerThemeLabel(context, value),
                    leadingOf: (value) => _ThemeSwatch(mode: value),
                    onChanged: notifier.updateTheme,
                    background: background,
                    foreground: foreground,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingChoiceRow<T> extends StatelessWidget {
  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final Widget Function(T value)? leadingOf;
  final Future<void> Function(T value) onChanged;
  final Color background;
  final Color foreground;

  const _SettingChoiceRow({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    this.leadingOf,
    required this.onChanged,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor = Color.alphaBlend(
      foreground.withValues(alpha: 0.12),
      background,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foreground.withValues(alpha: 0.68),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final value in values)
              ChoiceChip(
                selected: value == selected,
                showCheckmark: false,
                backgroundColor: Colors.transparent,
                selectedColor: selectedColor,
                side: BorderSide(
                  color: value == selected
                      ? foreground.withValues(alpha: 0.32)
                      : foreground.withValues(alpha: 0.14),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                labelStyle: TextStyle(
                  color: foreground,
                  fontWeight: value == selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leadingOf != null) ...[
                      leadingOf!(value),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(labelOf(value)),
                  ],
                ),
                onSelected: (isSelected) {
                  if (isSelected) onChanged(value);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final ReaderThemeMode mode;

  const _ThemeSwatch({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: mode.background,
        shape: BoxShape.circle,
        border: Border.all(color: mode.foreground.withValues(alpha: 0.32)),
      ),
    );
  }
}

class _LoadingSheet extends StatelessWidget {
  const _LoadingSheet();

  @override
  Widget build(BuildContext context) {
    return const Material(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      child: SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorSheet extends StatelessWidget {
  final Object error;

  const _ErrorSheet({required this.error});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      child: SizedBox(
        height: 220,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(context.l10n.settingsLoadFailed(error)),
          ),
        ),
      ),
    );
  }
}
