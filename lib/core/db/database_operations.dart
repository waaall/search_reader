// 数据库复合操作：集中维护跨表删除规则，供 DAO 与启动恢复流程复用。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> deleteBookRecords(Database db, int bookId) async {
  await db.transaction((txn) => deleteBookRecordsInTransaction(txn, bookId));
}

Future<void> deleteBookRecordsInTransaction(
  DatabaseExecutor txn,
  int bookId,
) async {
  // FTS5 不是 books 的外键子表，删除书籍前必须按章节 rowid 手动清理。
  final chapterRows = await txn.query(
    'chapters',
    columns: ['id'],
    where: 'book_id = ?',
    whereArgs: [bookId],
  );
  for (final row in chapterRows) {
    await txn.delete(
      'chapters_fts',
      where: 'rowid = ?',
      whereArgs: [row['id']],
    );
  }
  await txn.delete('books', where: 'id = ?', whereArgs: [bookId]);
}
