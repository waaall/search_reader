# 技术设计文档

> 版本：v0.1（2026-05-14）
> 对应产品需求：[01-product-requirements.md](./01-product-requirements.md)

## 1. 技术栈选型

| 层 | 选型 | 选择理由 |
|---|---|---|
| UI 框架 | **Flutter 3.x（stable）** | 全平台像素级一致渲染、移动端原生体验、单语言生态、文本渲染成熟 |
| 语言 | **Dart 3.x** | Flutter 唯一官方语言，空安全成熟 |
| 状态管理 | **Riverpod 2.x** | 社区主流、可测试、编译期安全、无需 BuildContext |
| 本地存储 | **sqflite + sqflite_common_ffi** | 跨平台 SQLite，桌面端通过 ffi 支持 |
| 全文索引 | **SQLite FTS5（unicode61 + Dart 侧 bigram 化）** | 内置无外部依赖；自切 bigram 让 ≥2 字关键词可搜（trigram 至少 3 字）|
| 编码检测 | **charset_converter + 自实现策略** | 支持 GBK/GB18030/UTF-8/UTF-16 |
| 文件选择 | **file_picker** | 跨平台 + Android SAF 兼容 |
| epub 解析 | **epubx + html + archive** | epubx 读 epub，html 抽纯文本，archive 处理"解压目录形式"的 epub |
| 路径管理 | **path_provider** | 跨平台沙盒目录抽象 |
| 国际化 | **intl + flutter_localizations** | MVP 仅中文，但留好基础设施 |

**已排除的选项与原因**：
- PySide：Android 几乎不可用，分发体积巨大
- Tauri：移动端生态新、各平台 WebView 渲染差异是阅读器硬伤
- Flutter 之外的 Compose Multiplatform / KMP：Android 之外的桌面端成熟度暂时不如 Flutter

## 2. 整体架构

采用经典三层 + 功能切片：

```
┌──────────────────────────────────────────┐
│            features/  功能层              │
│  importer  library  reader  search       │
│            settings                       │
└──────────────────────────────────────────┘
                 ↓ 依赖
┌──────────────────────────────────────────┐
│            domain/  领域层                │
│  Book  Chapter  ReadingProgress          │
│  ReaderSettings                          │
└──────────────────────────────────────────┘
                 ↓ 依赖
┌──────────────────────────────────────────┐
│            core/  基础设施层              │
│  db   storage   encoding   parser        │
└──────────────────────────────────────────┘
```

**依赖方向**：features → domain → core，反向不允许。features 之间不互相直接依赖，通过 domain 实体或 Riverpod provider 通信。

## 3. 项目目录结构

```
lib/
├── main.dart                      # 入口，初始化数据库、Riverpod 容器
├── app.dart                       # MaterialApp 与路由
│
├── core/
│   ├── db/
│   │   ├── database.dart          # 数据库打开、迁移
│   │   └── schema.sql             # 表结构（DDL，作为常量内嵌）
│   ├── storage/
│   │   └── book_storage.dart      # 沙盒目录、文件拷贝
│   ├── encoding/
│   │   └── text_decoder.dart      # 编码检测与解码
│   └── parser/
│       ├── book_format.dart       # 抽象接口
│       ├── txt_parser.dart        # txt 解析（章节切分）
│       └── epub_parser.dart       # epub 解析（HTML → 纯文本，兼容目录形式）
│
├── domain/
│   ├── book.dart                  # Book 实体
│   ├── chapter.dart               # Chapter 实体
│   ├── reading_progress.dart      # 阅读进度实体
│   └── reader_settings.dart       # 阅读器设置实体
│
├── features/
│   ├── importer/
│   │   ├── importer_service.dart  # 导入流程编排
│   │   └── import_progress.dart   # 进度状态
│   ├── library/
│   │   ├── library_page.dart      # 书架页面
│   │   ├── library_provider.dart  # 状态
│   │   └── widgets/
│   ├── reader/
│   │   ├── reader_page.dart       # 阅读页面
│   │   ├── pagination.dart        # 分页引擎
│   │   ├── reader_provider.dart   # 阅读状态
│   │   └── widgets/
│   ├── search/
│   │   ├── search_page.dart       # 搜索页面
│   │   ├── search_service.dart    # FTS5 查询封装
│   │   └── widgets/
│   └── settings/
│       ├── settings_page.dart
│       └── settings_provider.dart
│
└── shared/
    ├── widgets/                   # 通用组件
    └── theme/
        └── app_theme.dart         # 三套主题定义

test/
├── core/
└── features/

docs/
└── demand/                        # 需求文档（本文档所在）
```

## 4. 数据模型

### 4.1 关系数据库 Schema

```sql
-- 书籍主表
CREATE TABLE books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  author TEXT,
  file_path TEXT NOT NULL,         -- 沙盒内相对路径
  encoding TEXT NOT NULL,          -- 检测到的原始编码（utf-8/gbk 等）
  total_chars INTEGER NOT NULL,    -- 总字数（解码后）
  created_at INTEGER NOT NULL,     -- 导入时间（毫秒时间戳）
  last_read_at INTEGER             -- 最近阅读时间
);

-- 章节表
CREATE TABLE chapters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  chapter_index INTEGER NOT NULL,  -- 章节序号（0-based）
  title TEXT NOT NULL,             -- 章节标题（原文，UI 展示用）
  start_char INTEGER NOT NULL,     -- 在原文中的起始字符位置
  end_char INTEGER NOT NULL,       -- 在原文中的结束字符位置
  content TEXT NOT NULL,           -- 章节正文（搜索结果生成 snippet 用）
  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
);
CREATE INDEX idx_chapters_book ON chapters(book_id, chapter_index);

-- 阅读进度（每本书一条）
CREATE TABLE reading_progress (
  book_id INTEGER PRIMARY KEY,
  chapter_index INTEGER NOT NULL,
  char_offset INTEGER NOT NULL,    -- 章节内字符偏移
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
);

-- 全文索引（FTS5，unicode61 分词器；title/search 列存 Dart 侧 bigram 化的 token 序列）
CREATE VIRTUAL TABLE chapters_fts USING fts5(
  title,                            -- bigram 化后的章节标题（用于搜索）
  search,                           -- bigram 化后的章节正文（用于搜索）
  tokenize='unicode61'              -- 按空白切分；每个 bigram 在序列中作为一个完整 token
);
-- 不用 contentless（content=''）：老版本 SQLite 的 contentless 表 DELETE 不支持
-- 代价：FTS5 表内多存一份 bigram 序列（约原文 2x）

-- 用户偏好设置（单行表）
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- 书签：精确到章节内字符偏移；可选备注
-- (book_id, chapter_index, char_offset) 唯一约束保证去重，重复加书签时 REPLACE 覆盖 note
CREATE TABLE bookmarks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  chapter_index INTEGER NOT NULL,
  char_offset INTEGER NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_bookmarks_pos
  ON bookmarks(book_id, chapter_index, char_offset);
CREATE INDEX idx_bookmarks_book
  ON bookmarks(book_id, created_at DESC);
```

**Schema 设计要点**：
- `chapters.content` 存章节原文，用于搜索结果生成 snippet（不依赖 FTS5 内部内容）
- reader 仍走"沙盒文件 + 起止位置截取"的路径，与 `chapters.content` 互不依赖
- FTS5 用 **unicode61 + Dart 侧 bigram 化**：原文 `"你好世界"` → 索引序列 `"你好 好世 世界"`，每个 bigram 作为一个 token；搜索 `"你好"` 命中第一个 token
- 查询同样 bigram 化 + 紧邻短语：`"你好世"` → `("你好" + "好世")`，等价于原文连续出现 `"你好世"`
- 删除书籍时通过 `ON DELETE CASCADE` 级联清理章节与进度，FTS5 需要手动按 rowid 清理

### 4.2 领域实体（Dart）

```dart
class Book {
  final int id;
  final String title;
  final String? author;
  final String filePath;
  final String encoding;
  final int totalChars;
  final DateTime createdAt;
  final DateTime? lastReadAt;
}

class Chapter {
  final int id;
  final int bookId;
  final int chapterIndex;
  final String title;
  final int startChar;
  final int endChar;
}

class ReadingProgress {
  final int bookId;
  final int chapterIndex;
  final int charOffset;
  final DateTime updatedAt;
}

class ReaderSettings {
  final FontSize fontSize;       // small / medium / large / extraLarge
  final LineHeight lineHeight;   // compact / normal / relaxed
  final ReaderTheme theme;       // light / dark / sepia
}
```

## 5. 关键模块设计

### 5.1 编码检测（core/encoding/text_decoder.dart）

```
策略（按顺序尝试）：
1. 检查 BOM
   - EF BB BF       → UTF-8
   - FF FE          → UTF-16 LE
   - FE FF          → UTF-16 BE
2. 尝试 UTF-8 严格解码（allowMalformed=false）成功 → UTF-8
3. 失败则用 GBK / GB18030 解码（charset_converter）
4. 仍失败时给出明确错误，不进入沉默 fallback
```

输出：`DecodedText { content: String, encoding: String }`

### 5.2 章节解析（core/parser/txt_parser.dart）

正则模式（按行匹配，行首允许空格 / 全角空格）：

```dart
final _chapterPattern = RegExp(
  r'^[\s　]*('
  r'第[零一二三四五六七八九十百千万0-9]+[章节回部卷]'   // 中文章节
  r'|序[章言幕]|楔子|引子|尾声|后记|前言'              // 特殊标题
  r'|Chapter\s+\d+'                                  // 英文兼容
  r')[\s\S]{0,40}$',                                 // 标题行长度上限
  multiLine: true,
);
```

输出：`List<ParsedChapter { title, startChar, endChar }>`。
- 没匹配到任何章节 → 整本书作为单章节，标题取书名
- 章节内容 = 文本中两个章节标题之间的部分

### 5.3 分页引擎（features/reader/pagination.dart）

**策略**：按章节独立分页（不跨章节），实时根据当前字号 / 行距 / 屏幕尺寸计算。

```
输入：章节文本 + 显示参数（屏幕宽/高、字号、行距、内边距、字体）
处理：用 Flutter TextPainter 测量
  1. 把章节文本切成段落
  2. 每段落用 TextPainter 计算实际渲染高度
  3. 累计高度，达到页面可显示高度时切页
  4. 输出：List<Page { startCharInChapter, endCharInChapter, content }>
缓存：当前章节的分页结果。换章节时重算，换字号时清缓存
```

性能预算：单章节（1-3 万字）分页计算 ≤ 100 ms。

### 5.4 全文搜索（features/search/search_service.dart + core/db/text_index.dart）

**索引侧（导入时）**：每章节正文经 `toBigramTokens()` 切成 `"你好 好世 世界"` 这种 bigram 序列，写入 `chapters_fts.search`。FTS5 的 unicode61 分词器按空格切，每个 bigram 作为一个完整 token 入倒排索引。

**查询侧**：用户输入经 `toBigramQuery()` 处理：
- `"你好"` → `'"你好"'`（单 token）
- `"你好世"` → `'("你好" + "好世")'`（FTS5 phrase 紧邻短语，等价原文连续）
- `"剑客 武功"` → `'"剑客" AND "武功"'`（多组之间 AND）

**SQL**：
```sql
SELECT
  b.id, b.title, c.id, c.chapter_index, c.title, c.content
FROM chapters_fts
JOIN chapters c ON chapters_fts.rowid = c.id
JOIN books b ON c.book_id = b.id
WHERE chapters_fts MATCH ?    -- bigram 化后的 FTS5 表达式
ORDER BY rank
LIMIT 100;
```

**Snippet**：FTS5 内部存的是 bigram 序列，自带 `snippet()` 出来的位置不映射回原文。改在 Dart 侧 `makeSnippet(content, rawQuery)` 从 `chapters.content` 找匹配位置 ±24 字符截取，加 `<mark>` 高亮。

- 用 `rank` 排序（FTS5 BM25 默认）
- 结果点击 → 路由到 `reader_page` 并定位到 `chapter_index + char_offset`

### 5.5 文件存储（core/storage/book_storage.dart）

```
导入流程：
1. file_picker 拿到原文件路径（Android 走 SAF，桌面端为绝对路径）
2. 持久化到 path_provider.getApplicationDocumentsDirectory()/books/{uuid}.<ext>
   - txt：原文件 copy，保留原编码（reader 读盘时再解码）
   - epub：解析后只把抽取出的纯文本以 utf-8 .txt 写入（原 epub 不落盘）
3. 数据库 books.file_path 存相对路径（不存绝对路径，避免沙盒迁移失效）
4. 后续读取时：appDocs + 相对路径 → 绝对路径
```

## 6. 跨平台关键事项

### 6.1 Android
- 最低 SDK 26，目标 SDK 跟随 Flutter stable 默认
- Storage Access Framework：`file_picker` 默认走 SAF，无需额外申请存储权限
- SQLite FTS5 unicode61：所有 SQLite 版本都内置（无需额外编译选项），Android 系统 SQLite 全覆盖

### 6.2 macOS
- 沙盒：默认 enabled，需要在 `macos/Runner/*.entitlements` 中开启 `com.apple.security.files.user-selected.read-only` 才能选文件
- 因为我们拷贝到 app 沙盒，不需要持续访问书签（security-scoped bookmark）

### 6.3 Windows
- sqflite 在 Windows 上必须用 `sqflite_common_ffi` 初始化
- 需要 Visual Studio 2022 + "Desktop development with C++" 工作负载

### 6.4 Linux
- 同 Windows，需要 ffi 后端
- 构建依赖：`clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`

## 7. 状态管理约定

- 全局只读单例（数据库连接、settings 缓存）：用 Riverpod `Provider`
- 页面状态（书架列表、当前阅读位置）：用 `AsyncNotifierProvider` / `NotifierProvider`
- 跨页面共享但生命周期短的数据：避免，宁可重新查询数据库
- 不使用 setState（除非是非常局部的纯 UI 状态）

## 8. 测试策略

- core/ 模块（编码检测、章节解析、数据库操作）：单元测试覆盖
- features/ 模块：核心业务逻辑（importer、search、pagination）单测
- UI 层：MVP 阶段不强求 widget test，手工验证为主

## 9. 已识别的技术风险

| 风险 | 影响 | 应对 |
|---|---|---|
| Android 第一次构建踩 Gradle / NDK / JDK 版本 | 阻塞 | 文档化构建步骤；遇到时单独定位 |
| FTS5 索引体积约为原文 3-5x（chapters.content 1x + FTS5 内部 bigram 序列 2x + 倒排索引 ~2x）| 占用大 | MVP 接受；远期可改 contentless 模式（需保证最低 SQLite 3.43+）|
| 1 字符的关键词搜不到（bigram 最低 2 字）| 短词搜索失效 | 文档明确"≥2 字符"；如需 1 字搜索，再加 LIKE 兜底分支 |
| TextPainter 在不同平台字体度量微差 | 分页结果略不同 | 接受差异（同一设备稳定即可），不强求跨平台一致 |
| 大文件（>10MB）UI 卡顿 | 体验下降 | MVP 不优化，文档明确范围；后续用 Isolate + 流式解析 |
| GBK 文件少见的字符解码失败 | 个别小说乱码 | 使用 GB18030（GBK 超集）；仍失败时提示并允许跳过 |

## 10. 编码与协作规范

- 关键步骤代码写**简洁的中文注释**（说"为什么"，不说"做什么"）
- 模块化优先：避免硬编码、避免单文件超过 400 行
- 不主动生成总结性文档（除非用户要求）
- 提交前 `flutter analyze` 必须无 error
- 命名：英文，避免中文标识符
