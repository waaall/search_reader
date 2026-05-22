import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../domain/bookmark.dart';
import '../bookmarks/all_bookmarks_provider.dart';

// 某本书的书签列表 provider，按 bookId family 化
class BookmarksNotifier extends FamilyAsyncNotifier<List<Bookmark>, int> {
  final BookmarkDao _dao = BookmarkDao();

  @override
  Future<List<Bookmark>> build(int bookId) async {
    return _dao.listByBook(bookId);
  }

  // 加书签：相同 (chapter, offset) 已存在时覆盖 note
  Future<void> add({
    required int chapterIndex,
    required int charOffset,
    String? note,
  }) async {
    await _dao.upsert(
      bookId: arg,
      chapterIndex: chapterIndex,
      charOffset: charOffset,
      note: note,
    );
    state = AsyncData(await _dao.listByBook(arg));
    // 跨书全局书签页是 app 级 provider，需失效以同步新增
    ref.invalidate(allBookmarksProvider);
  }

  Future<void> remove(int id) async {
    await _dao.delete(id);
    state = AsyncData(await _dao.listByBook(arg));
    ref.invalidate(allBookmarksProvider);
  }
}

final bookmarksProvider =
    AsyncNotifierProvider.family<BookmarksNotifier, List<Bookmark>, int>(
  BookmarksNotifier.new,
);
