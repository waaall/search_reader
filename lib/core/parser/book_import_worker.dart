// 导入 worker：只接收可跨 isolate 传递的路径和限制，解析结果通过临时正文文件返回。
import 'dart:io';
import 'dart:isolate';

import 'book_format.dart';
import 'epub_parser.dart';
import 'import_limits.dart';
import 'txt_parser.dart';

class BookImportWorker {
  const BookImportWorker._();

  static Future<BookImportManifest> run({
    required String inputPath,
    required String outputPath,
    required String extension,
    ImportLimits limits = ImportLimits.defaults,
  }) async {
    final request = <String, Object?>{
      'inputPath': inputPath,
      'outputPath': outputPath,
      'extension': extension,
      'limits': limits.toMap(),
    };
    final result = await Isolate.run(() => runBookImportWorker(request));
    return BookImportManifest.fromMap(Map<Object?, Object?>.from(result));
  }
}

// 顶层函数不捕获 UI 对象，保证 Isolate.run 能在 Android、桌面端复用。
Future<Map<String, Object?>> runBookImportWorker(
  Map<String, Object?> request,
) async {
  final inputPath = request['inputPath']! as String;
  final outputPath = request['outputPath']! as String;
  final extension = request['extension']! as String;
  final limits = ImportLimits.fromMap(
    Map<Object?, Object?>.from(request['limits']! as Map),
  );

  try {
    final manifest = switch (extension.toLowerCase()) {
      '.txt' => await TxtParser().parseToFile(
        inputPath,
        outputPath,
        limits: limits,
      ),
      '.epub' => await EpubParser().parseToFile(
        inputPath,
        outputPath,
        limits: limits,
      ),
      _ => throw ArgumentError('不支持的导入格式：$extension'),
    };
    return manifest.toMap();
  } catch (_) {
    try {
      await File(outputPath).delete();
    } catch (_) {}
    rethrow;
  }
}
