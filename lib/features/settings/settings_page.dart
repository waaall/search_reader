// 设置页界面：用轻量卡片区分系统设置与阅读设置，并让阅读参数在预览区实时反馈。
// 所有选项仍由现有 Provider 持久化，本文件只调整设置页的展示与交互方式。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reader_settings.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/theme/app_tokens.dart';
import '../../shared/widgets/app_animated_switcher.dart';
import 'app_locale_provider.dart';
import 'reader_settings_labels.dart';
import 'settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final asyncSettings = ref.watch(readerSettingsProvider);
    final asyncLocale = ref.watch(appLocaleProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: AppAnimatedSwitcher(
        child: _buildAsyncBody(context, ref, asyncSettings, asyncLocale),
      ),
    );
  }

  Widget _buildAsyncBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ReaderSettings> asyncSettings,
    AsyncValue<AppLocaleMode> asyncLocale,
  ) {
    final l10n = context.l10n;
    if (asyncSettings.isLoading || asyncLocale.isLoading) {
      return const Center(
        key: ValueKey('settings-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (asyncSettings.hasError) {
      return Center(
        key: const ValueKey('settings-error'),
        child: Text(l10n.loadFailed(asyncSettings.error!)),
      );
    }
    if (asyncLocale.hasError) {
      return Center(
        key: const ValueKey('settings-locale-error'),
        child: Text(l10n.loadFailed(asyncLocale.error!)),
      );
    }
    return _SettingsBody(
      key: const ValueKey('settings-content'),
      settings: asyncSettings.requireValue,
      localeMode: asyncLocale.requireValue,
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final ReaderSettings settings;
  final AppLocaleMode localeMode;

  const _SettingsBody({
    super.key,
    required this.settings,
    required this.localeMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settingsNotifier = ref.read(readerSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsCard(
                  title: l10n.systemSettingsSection,
                  child: _LanguageSettingRow(
                    valueLabel: _localeLabel(context, localeMode),
                    onTap: () => _selectLanguage(context, ref),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _SettingsCard(
                  title: l10n.readingSettingsSection,
                  child: Column(
                    children: [
                      _SettingBlock(
                        title: l10n.fontSizeSection,
                        trailing: _FontSizeStepper(
                          value: settings.fontSize,
                          onChanged: settingsNotifier.updateFontSize,
                        ),
                      ),
                      const _SettingDivider(),
                      _SettingBlock(
                        title: l10n.lineHeightSection,
                        content: _EnumSegmentedControl<LineHeightLevel>(
                          values: LineHeightLevel.values,
                          current: settings.lineHeight,
                          labelOf: (value) =>
                              readerLineHeightLabel(context, value),
                          onChanged: settingsNotifier.updateLineHeight,
                        ),
                      ),
                      const _SettingDivider(),
                      _SettingBlock(
                        title: l10n.readerThemeSection,
                        content: _ThemeChooser(
                          current: settings.theme,
                          onChanged: settingsNotifier.updateTheme,
                        ),
                      ),
                      const _SettingDivider(),
                      _SettingBlock(
                        title: l10n.readingModeSection,
                        content: _EnumSegmentedControl<ReadingMode>(
                          values: ReadingMode.values,
                          current: settings.readingMode,
                          labelOf: (value) => readingModeLabel(context, value),
                          iconOf: (value) => switch (value) {
                            ReadingMode.paginated =>
                              Icons.auto_stories_outlined,
                            ReadingMode.scroll => Icons.swap_vert_rounded,
                          },
                          onChanged: settingsNotifier.updateReadingMode,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _Preview(settings: settings),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 语言作为普通设置行呈现，具体选项在底部弹层中完成选择。
  Future<void> _selectLanguage(BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<AppLocaleMode>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => _LanguagePickerSheet(current: localeMode),
    );
    if (selected == null || selected == localeMode || !context.mounted) return;
    await ref.read(appLocaleProvider.notifier).updateLocaleMode(selected);
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 0,
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _LanguageSettingRow extends StatelessWidget {
  final String valueLabel;
  final VoidCallback onTap;

  const _LanguageSettingRow({required this.valueLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${context.l10n.displayLanguage}, $valueLabel',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.translate_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  context.l10n.displayLanguage,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Text(
                valueLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguagePickerSheet extends StatelessWidget {
  final AppLocaleMode current;

  const _LanguagePickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.displayLanguage,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final mode in AppLocaleMode.values)
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              title: Text(_localeLabel(context, mode)),
              trailing: mode == current
                  ? Icon(Icons.check_rounded, color: colorScheme.primary)
                  : null,
              selected: mode == current,
              selectedTileColor: colorScheme.primaryContainer.withValues(
                alpha: 0.45,
              ),
              onTap: () => Navigator.of(context).pop(mode),
            ),
        ],
      ),
    );
  }
}

class _SettingBlock extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget? content;

  const _SettingBlock({required this.title, this.trailing, this.content})
    : assert(trailing != null || content != null);

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
    );

    if (trailing != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(child: titleWidget),
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleWidget,
          const SizedBox(height: AppSpacing.sm),
          content!,
        ],
      ),
    );
  }
}

class _SettingDivider extends StatelessWidget {
  const _SettingDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _FontSizeStepper extends StatelessWidget {
  final FontSizeLevel value;
  final Future<void> Function(FontSizeLevel) onChanged;

  const _FontSizeStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final values = FontSizeLevel.values;
    final index = values.indexOf(value);
    final previous = index > 0 ? values[index - 1] : null;
    final next = index < values.length - 1 ? values[index + 1] : null;
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FontStepButton(
            label: 'A−',
            enabled: previous != null,
            onPressed: previous == null
                ? null
                : () {
                    onChanged(previous);
                  },
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 58),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: AppMotion.fast,
              child: Text(
                readerFontSizeLabel(context, value),
                key: ValueKey(value),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          _FontStepButton(
            label: 'A+',
            enabled: next != null,
            onPressed: next == null
                ? null
                : () {
                    onChanged(next);
                  },
          ),
        ],
      ),
    );
  }
}

class _FontStepButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  const _FontStepButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        foregroundColor: colorScheme.primary,
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EnumSegmentedControl<T extends Enum> extends StatelessWidget {
  final List<T> values;
  final T current;
  final String Function(T value) labelOf;
  final IconData Function(T value)? iconOf;
  final Future<void> Function(T value) onChanged;

  const _EnumSegmentedControl({
    required this.values,
    required this.current,
    required this.labelOf,
    this.iconOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: [
        for (final value in values)
          ButtonSegment<T>(
            value: value,
            icon: iconOf == null ? null : Icon(iconOf!(value), size: 18),
            label: Text(labelOf(value)),
          ),
      ],
      selected: {current},
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        onChanged(selection.first);
      },
    );
  }
}

class _ThemeChooser extends StatelessWidget {
  final ReaderThemeMode current;
  final Future<void> Function(ReaderThemeMode) onChanged;

  const _ThemeChooser({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final mode in ReaderThemeMode.values)
          Expanded(
            child: _ThemeChoice(
              mode: mode,
              selected: mode == current,
              onTap: () {
                onChanged(mode);
              },
            ),
          ),
      ],
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  final ReaderThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChoice({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = readerThemeLabel(context, mode);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mode.background,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: Text(
                  'Aa',
                  style: TextStyle(
                    color: mode.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final ReaderSettings settings;

  const _Preview({required this.settings});

  @override
  Widget build(BuildContext context) {
    final previewStyle = TextStyle(
      color: settings.theme.foreground,
      fontSize: settings.fontSize.size,
      height: settings.lineHeight.multiplier,
    );

    // 预览固定在阅读设置卡片底部，并保持固定高度，切换参数时只更新内部排版。
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.easeOut,
      height: 148,
      padding: const EdgeInsets.all(AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: settings.theme.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: settings.theme.foreground.withValues(alpha: 0.16),
        ),
      ),
      child: AnimatedDefaultTextStyle(
        duration: AppMotion.normal,
        curve: AppMotion.easeOut,
        style: previewStyle,
        child: Text(
          context.l10n.settingsPreviewText,
          maxLines: 4,
          overflow: TextOverflow.fade,
        ),
      ),
    );
  }
}

String _localeLabel(BuildContext context, AppLocaleMode mode) {
  final l10n = context.l10n;
  return switch (mode) {
    AppLocaleMode.system => l10n.languageSystem,
    AppLocaleMode.simplifiedChinese => l10n.languageSimplifiedChinese,
    AppLocaleMode.english => l10n.languageEnglish,
  };
}
