// 数据库增量迁移：正式 v1 作为基线，后续版本只逐级演进结构。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef DatabaseMigration = Future<void> Function(Database db);

// key 表示迁移完成后的目标版本，例如 2 表示 v1 → v2。
// 当前 v1 结构已经是最新基线，第一次改表时在这里登记 v2 迁移。
final Map<int, DatabaseMigration> _migrationsByTargetVersion =
    <int, DatabaseMigration>{};

Future<void> migrateDatabase(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion > newVersion) {
    throw StateError('不支持数据库降级：v$oldVersion → v$newVersion');
  }
  if (oldVersion == newVersion) return;

  // 逐版本执行，确保跳过多个版本时每一步都经过明确的结构变更。
  for (
    var targetVersion = oldVersion + 1;
    targetVersion <= newVersion;
    targetVersion++
  ) {
    final migration = _migrationsByTargetVersion[targetVersion];
    if (migration == null) {
      throw StateError('缺少数据库 v${targetVersion - 1} → v$targetVersion 的迁移');
    }
    await migration(db);
  }

  final violations = await db.rawQuery('PRAGMA foreign_key_check');
  if (violations.isNotEmpty) {
    throw StateError('数据库迁移产生了外键异常：$violations');
  }
}
