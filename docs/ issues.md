# issues

## 已解决但没有测试

| Bug | 改动 |
| --- | --- |
| #1 导入失败留坏书 | `importer_service.dart` 新增 `_rollback`，失败时连 `books` 行一起删（级联清章节） |
| #2 书架不刷新 | `reader_page.dart` `_ReaderShellState.dispose()` 里 `ref.invalidate(libraryProvider)` |
| #3 全局书签 stale | `bookmark_provider.dart` add/remove 后失效 `allBookmarksProvider` |
| #4 搜索跳转不到位 | `text_index.dart` 新增 `findMatchOffset`；`SearchHit` 加 `charOffset` 字段并透传到 `ReaderPage` |
| #5 迁移泄漏文件 | `book_storage.dart` 新增 `purgeAll()`，`onUpgrade` 调用 |