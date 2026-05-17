import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reader_settings.dart';
import '../../shared/l10n/app_l10n.dart';
import 'app_locale_provider.dart';
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
      body: _buildAsyncBody(context, ref, asyncSettings, asyncLocale),
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
      return const Center(child: CircularProgressIndicator());
    }
    if (asyncSettings.hasError) {
      return Center(child: Text(l10n.loadFailed(asyncSettings.error!)));
    }
    if (asyncLocale.hasError) {
      return Center(child: Text(l10n.loadFailed(asyncLocale.error!)));
    }
    return _buildBody(
      context,
      ref,
      asyncSettings.requireValue,
      asyncLocale.requireValue,
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ReaderSettings settings,
    AppLocaleMode localeMode,
  ) {
    final l10n = context.l10n;
    final settingsNotifier = ref.read(readerSettingsProvider.notifier);
    final localeNotifier = ref.read(appLocaleProvider.notifier);
    return ListView(
      children: [
        _section(l10n.systemSettingsSection),
        _settingLabel(l10n.displayLanguage),
        _segmentedEnum<AppLocaleMode>(
          values: AppLocaleMode.values,
          current: localeMode,
          labelOf: (v) => _localeLabel(context, v),
          onChanged: localeNotifier.updateLocaleMode,
        ),
        _section(l10n.readingSettingsSection),
        _settingLabel(l10n.fontSizeSection),
        _segmentedEnum<FontSizeLevel>(
          values: FontSizeLevel.values,
          current: settings.fontSize,
          labelOf: (v) => _fontSizeLabel(context, v),
          onChanged: settingsNotifier.updateFontSize,
        ),
        _settingLabel(l10n.lineHeightSection),
        _segmentedEnum<LineHeightLevel>(
          values: LineHeightLevel.values,
          current: settings.lineHeight,
          labelOf: (v) => _lineHeightLabel(context, v),
          onChanged: settingsNotifier.updateLineHeight,
        ),
        _settingLabel(l10n.readerThemeSection),
        _segmentedEnum<ReaderThemeMode>(
          values: ReaderThemeMode.values,
          current: settings.theme,
          labelOf: (v) => _themeLabel(context, v),
          onChanged: settingsNotifier.updateTheme,
        ),
        _settingLabel(l10n.readingModeSection),
        _segmentedEnum<ReadingMode>(
          values: ReadingMode.values,
          current: settings.readingMode,
          labelOf: (v) => _readingModeLabel(context, v),
          onChanged: settingsNotifier.updateReadingMode,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _Preview(settings: settings),
        ),
      ],
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  );

  Widget _settingLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  // 通用 enum 选择器：显示文本由调用方按当前 l10n 解析。
  Widget _segmentedEnum<T extends Enum>({
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required Future<void> Function(T) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<T>(
        segments: values
            .map((v) => ButtonSegment<T>(value: v, label: Text(labelOf(v))))
            .toList(),
        selected: {current},
        onSelectionChanged: (set) => onChanged(set.first),
      ),
    );
  }

  String _localeLabel(BuildContext context, AppLocaleMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      AppLocaleMode.system => l10n.languageSystem,
      AppLocaleMode.simplifiedChinese => l10n.languageSimplifiedChinese,
      AppLocaleMode.english => l10n.languageEnglish,
    };
  }

  String _fontSizeLabel(BuildContext context, FontSizeLevel level) {
    final l10n = context.l10n;
    return switch (level) {
      FontSizeLevel.small => l10n.fontSizeSmall,
      FontSizeLevel.medium => l10n.fontSizeMedium,
      FontSizeLevel.large => l10n.fontSizeLarge,
      FontSizeLevel.extraLarge => l10n.fontSizeExtraLarge,
    };
  }

  String _lineHeightLabel(BuildContext context, LineHeightLevel level) {
    final l10n = context.l10n;
    return switch (level) {
      LineHeightLevel.compact => l10n.lineHeightCompact,
      LineHeightLevel.normal => l10n.lineHeightNormal,
      LineHeightLevel.relaxed => l10n.lineHeightRelaxed,
    };
  }

  String _themeLabel(BuildContext context, ReaderThemeMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      ReaderThemeMode.light => l10n.readerThemeLight,
      ReaderThemeMode.dark => l10n.readerThemeDark,
      ReaderThemeMode.sepia => l10n.readerThemeSepia,
    };
  }

  String _readingModeLabel(BuildContext context, ReadingMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      ReadingMode.paginated => l10n.readingModePaginated,
      ReadingMode.scroll => l10n.readingModeScroll,
    };
  }
}

class _Preview extends StatelessWidget {
  final ReaderSettings settings;
  const _Preview({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: settings.theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        context.l10n.settingsPreviewText,
        style: TextStyle(
          color: settings.theme.foreground,
          fontSize: settings.fontSize.size,
          height: settings.lineHeight.multiplier,
        ),
      ),
    );
  }
}
