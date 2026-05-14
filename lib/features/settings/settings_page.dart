import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reader_settings.dart';
import 'settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(readerSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('阅读设置')),
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (settings) => _buildBody(context, ref, settings),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ReaderSettings s) {
    final notifier = ref.read(readerSettingsProvider.notifier);
    return ListView(
      children: [
        _section('字号'),
        _segmentedEnum<FontSizeLevel>(
          values: FontSizeLevel.values,
          current: s.fontSize,
          labelOf: (v) => switch (v) {
            FontSizeLevel.small => '小',
            FontSizeLevel.medium => '中',
            FontSizeLevel.large => '大',
            FontSizeLevel.extraLarge => '特大',
          },
          onChanged: notifier.updateFontSize,
        ),
        _section('行距'),
        _segmentedEnum<LineHeightLevel>(
          values: LineHeightLevel.values,
          current: s.lineHeight,
          labelOf: (v) => switch (v) {
            LineHeightLevel.compact => '紧凑',
            LineHeightLevel.normal => '标准',
            LineHeightLevel.relaxed => '宽松',
          },
          onChanged: notifier.updateLineHeight,
        ),
        _section('主题'),
        _segmentedEnum<ReaderThemeMode>(
          values: ReaderThemeMode.values,
          current: s.theme,
          labelOf: (v) => v.label,
          onChanged: notifier.updateTheme,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _Preview(settings: s),
        ),
      ],
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  // 通用 enum 选择器
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
}

class _Preview extends StatelessWidget {
  final ReaderSettings settings;
  const _Preview({required this.settings});

  static const _sampleText =
      '夜色如水，月光在屋檐上铺成薄薄一层霜。她合上书本，'
      '听到风穿过竹林的声音，像极了多年前在江南听过的那一阵。';

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
        _sampleText,
        style: TextStyle(
          color: settings.theme.foreground,
          fontSize: settings.fontSize.size,
          height: settings.lineHeight.multiplier,
        ),
      ),
    );
  }
}
