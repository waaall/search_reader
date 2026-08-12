# issues

## 数据库逻辑更新策略

已修复。数据库升级不再执行 drop & recreate，也不会清空 `books/`：

- `database_migrations.dart` 按目标版本注册增量迁移。
- v1 → v2 从旧 FTS 表恢复章节正文并重建 bigram 索引。
- v2 → v3 只新增书签表及索引。
- v3 → v4 通过新表复制元数据，移除 `chapters.content`。
- v4 → v5 新增 `import_jobs` 恢复日志表。
- 迁移由 sqflite 事务保护，完成后执行 `PRAGMA foreign_key_check`。
- 事务提交后才按 `books.file_path` 白名单删除无引用文件。

回归测试覆盖 v1、v2、v3、v4 直接升级到当前版本，验证以下数据：

- `books`、章节元数据和文件路径；
- `reading_progress`；
- `settings`；
- v3 已有的 `bookmarks`；
- 可用的 FTS5 搜索索引。

## 文件系统与数据库崩溃一致性

已修复。文件系统与 SQLite 无法共享同一个事务，因此采用“临时文件 + 数据库恢复日志 + 启动对账”的最终一致性协议：

- 文件先写入 `books/.staging/` 并刷新，再开始数据库事务。
- `books`、`chapters`、`chapters_fts`、`import_jobs` 在同一事务提交。
- 存在 `import_jobs` 的书籍不会出现在书架、阅读进度汇总或搜索结果中。
- 数据库提交后通过同一卷内 `rename` 原子发布正式文件，再删除导入日志。
- 启动时完成未发布导入，删除无章节/缺文件的坏书，修复缺失 FTS，并清理无引用正式文件和无日志临时文件。
- 删除书籍时以数据库事务成功为逻辑成功；文件删除失败不再显示为用户操作失败，残留文件由下次启动清理。


## 导入/索引可能卡 UI

导入时解析章节、生成 bigram、逐章写 FTS 都在主流程里执行：
/Users/zhengxu/Desktop/some_code/my-personal-git/search_reader/lib/core/db/daos.dart
10MB txt 或大 epub 时，用户可能感觉 App 卡住。后面最好把解析和索引放到 isolate，或者至少分批写入并让 UI 可取消。
