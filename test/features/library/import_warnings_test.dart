// 导入告警回归：批量导入、刷新与普通错误不能抹掉有损转换提示。
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/features/library/import_warnings_notice.dart';
import 'package:search_reader/features/library/library_provider.dart';
import 'package:search_reader/l10n/app_localizations.dart';

import '../../support/application_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('批量导入有损文本后仍展示告警，后续成功及刷新不清除告警', () async {
    final fixture = ApplicationFixture();
    await fixture.open();
    final container = ProviderContainer();
    try {
      final damaged = File(p.join(fixture.root.path, 'damaged.txt'));
      await damaged.writeAsBytes([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('正常正文'),
        0xFF,
      ]);
      final healthy = File(p.join(fixture.root.path, 'healthy.txt'));
      await healthy.writeAsString('完好正文');
      FilePicker.platform = _FilesPicker([damaged, healthy]);
      await container.read(libraryProvider.future);
      final notifier = container.read(libraryProvider.notifier);
      await notifier.pickAndImport();
      final imported = container.read(libraryProvider).requireValue;
      expect(imported.books, hasLength(2));
      expect(imported.error, isNull);
      expect(imported.decodingWarningTitles, ['damaged']);
      await notifier.refresh();
      expect(
        container.read(libraryProvider).requireValue.decodingWarningTitles,
        ['damaged'],
      );
      FilePicker.platform = _FilesPicker([healthy]);
      await notifier.pickAndImport();
      expect(
        container.read(libraryProvider).requireValue.decodingWarningTitles,
        ['damaged'],
      );
      notifier.dismissDecodingWarnings();
      expect(
        container.read(libraryProvider).requireValue.decodingWarningTitles,
        isEmpty,
      );
    } finally {
      container.dispose();
      await fixture.close();
    }
  });

  for (final language in ['en', 'zh']) {
    testWidgets('有损解码告警可本地化并关闭：$language', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ImportWarningsNotice(
              bookTitles: const ['示例书'],
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('示例书'), findsOneWidget);
      expect(find.textContaining('�'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });
  }

  testWidgets('大量告警在小屏幕上仍为书架保留空间', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              ImportWarningsNotice(
                bookTitles: List.generate(100, (index) => '包含很长名称的书籍 $index'),
                onDismiss: () {},
              ),
              const Expanded(child: Center(child: Text('书架内容'))),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ImportWarningsNotice)).height,
      lessThanOrEqualTo(120),
    );
    expect(find.text('书架内容'), findsOneWidget);
  });
}

class _FilesPicker extends FilePicker {
  final List<File> files;
  _FilesPicker(this.files);

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    for (final file in files)
      PlatformFile(
        name: p.basename(file.path),
        size: await file.length(),
        path: file.path,
      ),
  ]);
}
