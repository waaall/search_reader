# issues

## 数据库逻辑更新策略

已修复。数据库升级不再执行 drop & recreate，也不会清空 `books/`：

- `database_migrations.dart` 按目标版本注册增量迁移。
- v1 → v2 从旧 FTS 表恢复章节正文并重建 bigram 索引。
- v2 → v3 只新增书签表及索引。
- v3 → v4 通过新表复制元数据，移除 `chapters.content`。
- 迁移由 sqflite 事务保护，完成后执行 `PRAGMA foreign_key_check`。
- 事务提交后才按 `books.file_path` 白名单删除无引用文件。

回归测试覆盖 v1、v2、v3 直接升级到 v4，验证以下数据：

- `books`、章节元数据和文件路径；
- `reading_progress`；
- `settings`；
- v3 已有的 `bookmarks`；
- 可用的 FTS5 搜索索引。


## 导入/索引可能卡 UI

导入时解析章节、生成 bigram、逐章写 FTS 都在主流程里执行：
/Users/zhengxu/Desktop/some_code/my-personal-git/search_reader/lib/core/db/daos.dart
10MB txt 或大 epub 时，用户可能感觉 App 卡住。后面最好把解析和索引放到 isolate，或者至少分批写入并让 UI 可取消。
