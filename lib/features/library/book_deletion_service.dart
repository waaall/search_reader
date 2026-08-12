// 书籍删除服务：以数据库事务为逻辑提交点，文件删除采用可重试的尽力策略。
import '../../core/db/daos.dart';
import '../../core/storage/book_storage.dart';
import '../../domain/book.dart';

class BookDeletionService {
  BookDeletionService({BookDao? bookDao, BookStorage? storage})
    : _bookDao = bookDao ?? BookDao(),
      _storage = storage ?? BookStorage.shared;

  final BookDao _bookDao;
  final BookStorage _storage;

  Future<void> delete(Book book) async {
    await _bookDao.delete(book.id);
    try {
      await _storage.deleteFile(book.filePath);
    } catch (_) {
      // 数据库已经提交，残留文件会被下次启动的孤儿清理再次尝试删除。
    }
  }
}
