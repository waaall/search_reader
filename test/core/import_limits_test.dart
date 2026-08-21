// 导入限制回归测试：确保默认 EPUB 大小上限与产品策略保持一致。
import 'package:flutter_test/flutter_test.dart';
import 'package:search_reader/core/parser/import_limits.dart';

void main() {
  test('默认 EPUB 文件上限为 10 MiB', () {
    const expectedLimit = 10 * 1024 * 1024;

    expect(ImportLimits.defaultMaxEpubBytes, expectedLimit);
    expect(ImportLimits.defaults.limitForExtension('.epub'), expectedLimit);
  });
}
