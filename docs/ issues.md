# issues

## 已解决但没有测试

| Bug | 改动 |
| --- | --- |
| #1 导入失败留坏书 | `importer_service.dart` 新增 `_rollback`，失败时连 `books` 行一起删（级联清章节） |
| #2 书架不刷新 | `reader_page.dart` `_ReaderShellState.dispose()` 里 `ref.invalidate(libraryProvider)` |
| #3 全局书签 stale | `bookmark_provider.dart` add/remove 后失效 `allBookmarksProvider` |
| #4 搜索跳转不到位 | `text_index.dart` 新增 `findMatchOffset`；`SearchHit` 加 `charOffset` 字段并透传到 `ReaderPage` |
| #5 迁移泄漏文件 | `book_storage.dart` 新增 `purgeAll()`，`onUpgrade` 调用 |
| #6 分页缓存 | `reader_page.dart` `_ReaderShellState` 持有 `Pagination` 缓存，键 = 章节 | 字号 | 行距 | 宽 | 高，加书签等无关 rebuild 不再触发整章重新分页 |


### 问题7: 数据重复

chapters.content 把整本书又存了一份。这列只给搜索 snippet 用。沙盒已有全文,chapters 有 start_char/end_char —— 搜索完全可以像 reader 一样切文件生成 snippet。现状一本 5MB 的书:文件 5MB + content 5MB + FTS ~10MB。

| 改动 | 详情 |
| --- | --- |
| #7-a 抽 readFullText | `book_storage.dart` 新增 `readFullText`，`Reader`/`Search` 共用 |
| #7-b schema v4 | `database.dart` `_kDbVersion` 3→4，`chapters` 表去掉 `content TEXT NOT NULL` |
| #7-c DAO 改造 | `daos.dart` `ChapterDao.insertAll` 不再写 `content`；`SearchDao` 改为 `queryMatches`，返回 `ChapterMatchRow`（只有起止位置 + 文件路径） |
| #7-d Service 接手文件 I/O | `search_service.dart` 读沙盒文件、按 `[start, end)` 切片、生成 `snippet` + `charOffset`；同书多命中只读一次文件 |
| #7-e 文档 | `02-technical-design.md` §4.1 schema、设计要点、§5.6 SQL 与 snippet 描述全部对齐 |