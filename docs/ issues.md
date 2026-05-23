# issues

## 数据库逻辑更新策略

现在代码是这个策略：

- 升级 DB 时 drop & recreate
- 然后 `BookStorage.purgeAll()` 删除沙盒 `books/` 目录

结果是：

- 不会留下冗余旧文件
- 但用户书架、进度、书签都会丢，需要重新导入

这个最好做，当前基本已经做到。

---

#### 计划： 数据库逻辑更新后保留书架数据，只删冗余内容

目标：

- 保留 `books`
- 保留 `reading_progress`
- 保留 `bookmarks`
- 保留沙盒里的真实书籍文件
- 删除旧 `chapters.content` 冗余列
- 清理没有被 `books.file_path` 引用的孤儿文件

做法大概是：

1. `CREATE TABLE chapters_new (...)`，不含 `content`
2. 从旧 `chapters` 复制元信息：
   ```sql
   INSERT INTO chapters_new(id, book_id, chapter_index, title, start_char, end_char)
   SELECT id, book_id, chapter_index, title, start_char, end_char FROM chapters;
   ```
3. `DROP TABLE chapters`
4. `ALTER TABLE chapters_new RENAME TO chapters`
5. 重建索引
6. 清理沙盒中未被 `books.file_path` 引用的文件

这个方案不会保留冗余旧文件，也不会丢用户书架。

---
