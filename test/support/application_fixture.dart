// 应用级测试夹具：路径插件、数据库和书籍文件都隔离在临时目录中。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/db/daos.dart';
import 'package:search_reader/core/db/database.dart';
import 'package:search_reader/core/storage/book_storage.dart';
import 'package:search_reader/features/importer/import_progress.dart';
import 'package:search_reader/features/importer/importer_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ApplicationFixture {
  static const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  Database get db => AppDatabase.instance.db;
  BookStorage get storage => BookStorage(rootProvider: () async => root);

  Future<void> open() async {
    root = await Directory.systemTemp.createTemp('reader_stability_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return root.path;
          }
          throw MissingPluginException();
        });
    await AppDatabase.init();
  }

  Future<ImportResult> importBytes(String fileName, List<int> bytes) async {
    final source = File(p.join(root.path, fileName));
    await source.writeAsBytes(bytes);
    return ImporterService(
      importDao: BookImportDao(database: db),
      storage: storage,
    ).importFile(source.path);
  }

  Future<void> close() async {
    await AppDatabase.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await root.delete(recursive: true);
  }
}
