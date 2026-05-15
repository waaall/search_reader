import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../reader/bookmark_provider.dart';

// 跨书全局书签列表 provider
// 与每本书的 bookmarksProvider 独立维护：删除时同时刷新两边
class AllBookmarksNotifier extends AsyncNotifier<List<BookmarkWithMeta>> {
  final BookmarkDao _dao = BookmarkDao();

  @override
  Future<List<BookmarkWithMeta>> build() async {
    return _dao.listAll();
  }

  Future<void> refresh() async {
    state = AsyncData(await _dao.listAll());
  }

  // 删除：同时让对应书的 bookmarksProvider 失效，保证阅读器视图同步
  Future<void> remove(BookmarkWithMeta item) async {
    await _dao.delete(item.bookmark.id);
    ref.invalidate(bookmarksProvider(item.bookmark.bookId));
    state = AsyncData(await _dao.listAll());
  }
}

final allBookmarksProvider =
    AsyncNotifierProvider<AllBookmarksNotifier, List<BookmarkWithMeta>>(
  AllBookmarksNotifier.new,
);
