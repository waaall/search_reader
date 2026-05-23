# 技术设计文档

> 版本：v0.4（2026-05-23）
> 对应产品需求：[01-product-requirements.md](../demand/01-product-requirements.md)
> 构建与分发：[03-build-and-release.md](./03-build-and-release.md)

v0.3 补充：数据库后端从系统 SQLite 切换到全平台自带 `sqlite3` v3（修复 Android 系统 SQLite 缺 FTS5 导致的启动失败），新增数据库初始化失败的兜底错误页。

v0.4 补充：`chapters.content` 冗余列已移除，搜索 snippet 改为按章节起止位置切沙盒文件生成；阅读进度保存改为“写数据库 + 同步内存状态 + 串行化写入”，并在跳章/跳书签/搜索跳转/退出阅读页时立即保存，避免返回书架后再次进入仍回到旧位置。

## 1. 技术栈选型

| 层 | 选型 | 选择理由 |
|---|---|---|
| UI 框架 | **Flutter 3.x（stable）** | 全平台像素级一致渲染、移动端原生体验、单语言生态、文本渲染成熟 |
| 语言 | **Dart 3.x** | Flutter 官方语言，空安全成熟 |
| 状态管理 | **Riverpod 2.x** | 社区主流、可测试、编译期安全、无需 BuildContext |
| 本地存储 | **sqflite_common_ffi + sqlite3** | 全平台统一走 ffi；`sqlite3` v3 自带含 FTS5 的 SQLite，不依赖系统库 |
| 全文索引 | **SQLite FTS5（unicode61 + Dart 侧 bigram 化）** | FTS5 由自带 SQLite 提供；自切 bigram 让 ≥2 字关键词可搜 |
| 编码检测 | **enough_convert + 自实现策略** | 覆盖 UTF-8 / UTF-16 / GBK / GB18030 等中文小说常见编码 |
| 文件选择 | **file_picker** | 跨平台 + Android SAF 兼容 |
| epub 解析 | **epubx + html + archive** | epubx 读 epub，html 抽纯文本，archive 处理“解压目录形式”的 epub |
| 路径管理 | **path_provider + path** | 跨平台沙盒目录抽象与路径拼接 |
| 主题系统 | **flex_color_scheme + app_tokens** | 统一 Material 组件圆角 / 交互效果 / 间距 / 动效时长，减少硬编码 |
| 微动效 | **flutter_animate** | 列表、空状态、提示条等轻量入场动效，提升操作反馈 |
| 国际化 | **Flutter gen-l10n + ARB** | App UI 文案集中维护，语言切换可立即驱动全局重建，便于后续扩展更多语言 |

**已排除的选项与原因**：

- PySide：Android 几乎不可用，分发体积巨大。
- Tauri：移动端生态新，各平台 WebView 渲染差异是阅读器硬伤。
- Flutter 之外的 Compose Multiplatform / KMP：Android 之外的桌面端成熟度暂时不如 Flutter。

## 2. 整体架构

采用经典三层 + 功能切片：

```text
┌──────────────────────────────────────────┐
│            features/  功能层              │
│ importer library reader search bookmarks │
│ settings                                 │
└──────────────────────────────────────────┘
                 ↓ 依赖
┌──────────────────────────────────────────┐
│            domain/  领域层                │
│ Book Chapter ReadingProgress Bookmark    │
│ ReaderSettings                           │
└──────────────────────────────────────────┘
                 ↓ 依赖
┌──────────────────────────────────────────┐
│            core/  基础设施层              │
│ db storage encoding parser               │
└──────────────────────────────────────────┘
                 ↑ 被 UI 复用
┌──────────────────────────────────────────┐
│            shared/  共享层                │
│ theme widgets tokens                     │
└──────────────────────────────────────────┘
```

**依赖方向**：features → domain → core，shared 可被 features 引用但不反向依赖业务。features 之间尽量不互相直接依赖；需要跨功能通信时，通过 domain 实体、DAO 或 Riverpod provider 完成。

## 3. 项目目录结构

```text
lib/
├── main.dart                      # 入口：初始化数据库（失败则显示错误页）、Riverpod 容器
├── app.dart                       # MaterialApp、全局主题、国际化与首页
├── db_init_error_app.dart         # 数据库初始化失败的兜底错误页
├── l10n/                          # ARB 文案与 gen-l10n 生成代码
│   ├── app_en.arb
│   ├── app_zh.arb
│   └── app_localizations*.dart
│
├── core/
│   ├── db/
│   │   ├── database.dart          # 数据库打开、迁移、DDL
│   │   ├── daos.dart              # Book / Chapter / Progress / Bookmark / Settings DAO
│   │   └── text_index.dart        # bigram 索引与查询表达式构造
│   ├── storage/
│   │   └── book_storage.dart      # 沙盒目录、文件拷贝、全文读取、清理
│   ├── encoding/
│   │   └── text_decoder.dart      # 编码检测与解码
│   └── parser/
│       ├── book_format.dart       # 抽象解析结果
│       ├── txt_parser.dart        # txt 解析（章节切分）
│       └── epub_parser.dart       # epub 解析（HTML → 纯文本，兼容目录形式）
│
├── domain/
│   ├── book.dart                  # Book 实体
│   ├── bookmark.dart              # Bookmark 实体
│   ├── chapter.dart               # Chapter 实体
│   ├── reading_progress.dart      # 阅读进度实体
│   └── reader_settings.dart       # 阅读器字号/行距/主题/阅读模式
│
├── features/
│   ├── importer/
│   │   ├── importer_service.dart  # 导入流程编排
│   │   └── import_progress.dart   # 进度状态
│   ├── library/
│   │   ├── library_page.dart      # 书架页面
│   │   └── library_provider.dart  # 书架状态
│   ├── reader/
│   │   ├── reader_page.dart       # 阅读页面（翻页/滚动两种视图）
│   │   ├── pagination.dart        # 分页引擎
│   │   └── reader_provider.dart   # 阅读状态与进度保存
│   ├── search/
│   │   ├── search_page.dart       # 搜索页面
│   │   └── search_service.dart    # FTS5 查询封装
│   ├── bookmarks/
│   │   ├── all_bookmarks_page.dart
│   │   └── all_bookmarks_provider.dart
│   └── settings/
│       ├── app_locale_provider.dart # App 显示语言设置
│       ├── settings_page.dart
│       └── settings_provider.dart
│
└── shared/
    ├── l10n/                      # context.l10n 扩展与本地化格式化工具
    ├── widgets/                   # 通用组件
    └── theme/
        ├── app_theme.dart         # 非阅读页面 Material 主题
        └── app_tokens.dart        # 间距、圆角、动效时长 token

docs/
├── demand/
│   └── 01-product-requirements.md
└── dev/
    ├── 02-technical-design.md
    └── 03-build-and-release.md
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

-- 章节表：只存元信息与起止位置，正文与搜索 snippet 都按起止位置切沙盒文件
CREATE TABLE chapters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  chapter_index INTEGER NOT NULL,  -- 章节序号（0-based）
  title TEXT NOT NULL,
  start_char INTEGER NOT NULL,     -- 在全书纯文本中的起始字符位置
  end_char INTEGER NOT NULL,       -- 在全书纯文本中的结束字符位置
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

-- 全文索引：title/search 列存 Dart 侧 bigram 化的 token 序列
CREATE VIRTUAL TABLE chapters_fts USING fts5(
  title,
  search,
  tokenize='unicode61'
);

-- 用户偏好设置（key-value）
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- 书签：精确到章节内字符偏移；可选备注
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

- 阅读器正文与搜索 snippet 都按起止位置从沙盒文件切片（`BookStorage.readFullText`），避免在数据库里再保留一整份书。
- FTS5 用 **unicode61 + Dart 侧 bigram 化**：原文 `你好世界` → 索引序列 `你好 好世 世界`，每个 bigram 作为完整 token。
- 查询同样 bigram 化 + 紧邻短语：`你好世` → `("你好" + "好世")`，等价于原文连续出现 `你好世`。
- `bookmarks` 通过 `(book_id, chapter_index, char_offset)` 唯一约束去重；重复加书签时覆盖 note / created_at。
- 删除书籍时通过 `ON DELETE CASCADE` 级联清理章节、进度、书签；FTS5 需要在 DAO 中按 rowid 手动清理。
- 数据库升级当前采用 drop & recreate：旧数据会丢弃，需要重新导入。MVP 阶段接受该策略。

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

class Bookmark {
  final int id;
  final int bookId;
  final int chapterIndex;
  final int charOffset;
  final String? note;
  final DateTime createdAt;
}

enum ReadingMode { paginated, scroll }

class ReaderSettings {
  final FontSizeLevel fontSize;       // small / medium / large / extraLarge
  final LineHeightLevel lineHeight;   // compact / normal / relaxed
  final ReaderThemeMode theme;        // light / dark / sepia
  final ReadingMode readingMode;      // paginated / scroll
}
```

`settings` 表当前持久化以下 key：

| key | 说明 | 默认值 |
|---|---|---|
| `reader.font_size` | 阅读字号档位 | `medium` |
| `reader.line_height` | 阅读行距档位 | `normal` |
| `reader.theme` | 阅读器正文主题 | `light` |
| `reader.reading_mode` | 阅读模式 | `paginated` |
| `app.locale` | App 显示语言：`system` / `simplifiedChinese` / `english` | `system` |

## 5. 关键模块设计

### 5.1 编码检测（core/encoding/text_decoder.dart）

```text
策略（按顺序尝试）：
1. 检查 BOM
   - EF BB BF       → UTF-8
   - FF FE          → UTF-16 LE
   - FE FF          → UTF-16 BE
2. 尝试 UTF-8 严格解码（allowMalformed=false），成功则判定为 UTF-8
3. 失败则用 GB18030 / GBK 兼容路径解码
4. 仍失败时抛出明确错误，不进入沉默 fallback
```

输出：`DecodedText { content: String, encoding: String }`。

### 5.2 章节解析（core/parser/txt_parser.dart）

正则模式按行匹配，行首允许空格 / 全角空格，覆盖中文章节、序章 / 楔子 / 尾声、简单英文 `Chapter N` 等常见形式。

输出：`List<ParsedChapter { title, startChar, endChar, content }>`。

- 没匹配到任何章节 → 整本书作为单章节，标题取书名。
- 章节内容 = 文本中两个章节标题之间的部分。
- epub 导入先抽取章节纯文本，再复用统一的章节 / 索引 / 存储路径。

### 5.3 阅读状态与进度定位（features/reader/reader_provider.dart）

`readerProvider` 使用 `AsyncNotifierProvider.autoDispose.family`：

- 进入阅读页时读取书籍、章节、数据库进度，构造 `ReaderState`。
- 离开阅读页后 provider 允许自动销毁；但不能依赖“立即销毁”保证再次进入一定重读数据库。保存进度时必须同步更新 `ReaderState.initialCharOffset`，避免同一轮 App 运行期间复用旧内存状态。
- `prevChapter()` / `nextChapter()` / 目录 / 搜索 / 书签跳转会更新 `currentChapterIndex`、`initialCharOffset`，递增 `jumpToken`，并立即保存新的章节与偏移。
- 阅读视图的 `ValueKey` 包含 `jumpToken`，确保“换章 / 跳书签”时强制重建并定位到目标偏移。
- 普通翻页 / 滚动保存 `reading_progress` 时，同时更新 provider 内存态；若随后返回书架再进入同一本书，即使 provider 尚未释放，也应定位到最新位置。
- 阅读进度写入通过队列串行化：翻页、跳章、退出页可能连续触发保存，串行化可避免较早的异步写库后完成而覆盖较新的阅读位置。

阅读进度保存时机：

| 场景 | 保存内容 | 说明 |
|---|---|---|
| 翻页模式换页 | 当前页起始字符偏移 | `PageView.onPageChanged` 上报 |
| 滚动模式停止滚动 | 滚动比例映射出的章节内字符偏移 | `ScrollEndNotification` 上报 |
| 目录 / 上下章 / 书签 / 搜索跳转 | 目标章节 + 目标 offset | 跳转后立即落库，避免返回书架后丢位置 |
| 点击阅读页返回按钮或系统返回键 | 当前可见页 / 当前滚动位置 | 退出前先保存，再执行 `Navigator.pop()` |

### 5.4 阅读视图：翻页模式与滚动模式（features/reader/reader_page.dart）

阅读器根据 `ReaderSettings.readingMode` 选择两种视图：

| 模式 | 实现 | 进度策略 | 适用场景 |
|---|---|---|---|
| 翻页 `paginated` | `_PaginatedView` + `TextPaginator` | 当前页起始字符偏移 | 类 Kindle 翻页阅读 |
| 滚动 `scroll` | `_ScrollView` + `ScrollController` | 滚动比例映射章节字符偏移 | 连续滑动阅读 |

公共交互能力：

- 点击正文切换顶 / 底部菜单。
- 菜单支持上一章、下一章、目录和书签、添加书签、设置、返回。
- 返回按钮不直接 `pop`，而是先保存当前可见位置；系统返回键通过 `PopScope` 走同一保存逻辑。
- 目录/书签抽屉关闭只关闭 drawer，不应触发阅读页退出逻辑。
- 窄屏底部菜单采用等宽 `Expanded` + 图标上文字下布局，避免 5 个按钮横向溢出。
- 修改字号、行距、主题、阅读模式后，优先使用 `_lastCharOffset` 保留用户当前阅读位置。
- 发生跳章或书签跳转后清空 `_lastCharOffset`，改用 `ReaderState.initialCharOffset` 精确定位。

滚动模式的性能约束：

- 滚动进度百分比用 `ValueNotifier<double>` 局部刷新，避免每次滚动都重建大段正文 `Text`。
- 停止滚动时通过 `ScrollEndNotification` 保存进度，降低数据库写入频率。
- 当前位置按 `scrollOffset / maxScrollExtent` 映射到章节字符偏移；这是近似值，但足以用于恢复阅读位置。

### 5.5 分页引擎（features/reader/pagination.dart）

**策略**：按章节独立分页（不跨章节），实时根据当前字号 / 行距 / 屏幕尺寸计算。

```text
输入：章节文本 + 显示参数（屏幕宽/高、字号、行距、内边距、字体）
处理：用 Flutter TextPainter 测量
  1. 把章节文本切成段落
  2. 每段落用 TextPainter 计算实际渲染高度
  3. 累计高度，达到页面可显示高度时切页
  4. 输出：List<Page { startCharInChapter, endCharInChapter, content }>
缓存：当前章节的分页结果。换章节、换字号、换行距、尺寸变化时重算
```

阅读页在 `_ReaderShellState` 侧缓存当前章节分页结果，缓存键为：

```text
chapterIndex | fontSize | lineHeight | contentWidth | contentHeight
```

主题色、书签列表、菜单显隐等不影响布局的状态不进入缓存键，避免加书签或菜单刷新时重复执行整章 `TextPainter` 分页。

性能预算：单章节（1–3 万字）分页计算 ≤ 100 ms。

### 5.6 全文搜索（features/search/search_service.dart + core/db/text_index.dart）

**索引侧（导入时）**：每章节标题和正文经 `toBigramTokens()` 切成 bigram 序列，分别写入 `chapters_fts.title` / `chapters_fts.search`。

**查询侧**：用户输入经 `toBigramQuery()` 处理：

- `你好` → `"你好"`（单 token）。
- `你好世` → `("你好" + "好世")`（FTS5 phrase 紧邻短语）。
- `剑客 武功` → `"剑客" AND "武功"`（多组之间 AND）。

**SQL**：

```sql
SELECT
  b.id, b.title, b.file_path,
  c.id, c.chapter_index, c.title, c.start_char, c.end_char
FROM chapters_fts
JOIN chapters c ON chapters_fts.rowid = c.id
JOIN books b ON c.book_id = b.id
WHERE chapters_fts MATCH ?
ORDER BY rank
LIMIT 100;
```

**Snippet**：FTS5 内部存的是 bigram 序列，自带 `snippet()` 的位置不映射回原文。`SearchService` 拿到命中行后按 `(book.file_path, start_char, end_char)` 切沙盒文件得到原章节内容，再调用 `makeSnippet` / `findMatchOffset` 在 Dart 侧生成上下文片段与跳转字符偏移；同一本书的多个命中只读一次文件。

### 5.7 文件存储（core/storage/book_storage.dart）

```text
导入流程：
1. file_picker 拿到原文件路径（Android 走 SAF，桌面端为绝对路径）
2. 持久化到 path_provider.getApplicationDocumentsDirectory()/books/{uuid}.<ext>
   - txt：原文件 copy，保留原编码（reader 读盘时再解码）
   - epub：解析后只把抽取出的纯文本以 utf-8 .txt 写入（原 epub 不落盘）
3. 数据库 books.file_path 存相对路径（不存绝对路径，避免沙盒迁移失效）
4. 后续读取时：appDocs + 相对路径 → 绝对路径
5. `readFullText(relativePath)` 统一负责读取、编码检测、换行归一化；Reader 与 Search 共用，保证章节起止位置、搜索跳转 offset、书签 offset 的坐标一致
```

导入失败回滚：

- 导入流程先持久化沙盒文件，再写 `books`，最后批量写 `chapters` 与 FTS5。
- 若复制/解析/索引任一环节失败，`ImporterService._rollback` 会删除已写入的 `books` 行（级联清章节/进度/书签）与沙盒文件。
- 回滚自身异常不覆盖真实导入错误；UI 展示原始导入失败原因。

数据库迁移清理：

- 当前升级策略仍是 drop & recreate：旧数据库行全部丢弃。
- 因旧书记录被丢弃，`onUpgrade` 会调用 `BookStorage.purgeAll()` 清空沙盒 `books/` 目录，避免留下无法被书架引用的旧文件。
- 若后续改为保留书架数据的精细迁移，需要增加“按 `books.file_path` 白名单清理孤儿文件”的流程。

### 5.8 主题、设计 token 与动效（shared/theme）

App 主题分两层：

1. **非阅读页面 Material 主题**：`AppTheme.light()` / `AppTheme.dark()` 基于 `flex_color_scheme` 生成，统一组件圆角、卡片阴影、交互效果与禁用态色彩。
2. **阅读器正文主题**：`ReaderThemeMode` 独立控制正文背景和文字颜色，不受系统 Material 主题直接影响，避免阅读体验随外层组件主题漂移。

`app_tokens.dart` 收纳 widget 层常用数值：

| token | 说明 |
|---|---|
| `AppSpacing` | `xs/sm/md/lg/xl` 间距阶梯 |
| `AppRadius` | `sm/md/lg` 圆角阶梯 |
| `AppMotion` | `fast/normal` 动效时长 |

当前使用 `flutter_animate` 的位置：

- 书架列表项错峰淡入 / 上滑。
- 书架空状态、导入提示、错误提示入场动效。
- 全部书签页分组标题、书签项、空状态淡入。
- 搜索结果项淡入。

### 5.9 App UI 国际化（l10n）

第一版只支持 **简体中文** 与 **English**，默认语言策略为“跟随系统”。语言设置作为 App 级偏好持久化到 `app.locale`，由 `appLocaleProvider` 驱动 `MaterialApp.locale`；用户在设置页切换后，无需重启即可全局刷新。

实现约定：

- 使用 Flutter 官方 `gen-l10n`：源文案集中在 `lib/l10n/app_zh.arb` 与 `lib/l10n/app_en.arb`，生成代码为 `AppLocalizations`。
- UI 通过 `context.l10n` 读取文案；日期相对时间、字数、导入阶段、结构化错误等动态文本统一放在 `shared/l10n/app_formatters.dart` 中按当前语言生成。
- 领域层与 enum 不保存显示文本，只保存稳定逻辑值（例如 `ReadingMode.paginated`、`ReaderThemeMode.light`）。
- 只翻译 App UI；书名、章节标题、正文、搜索片段、书签备注等用户数据保持原文。
- 用户友好的错误标题 / 前缀走 l10n，底层异常详情原样显示，便于排查。

## 6. 跨平台关键事项

### 6.1 Android

- 当前 `android/app/build.gradle.kts` 使用 Flutter 默认 SDK 值：`compileSdk = 36`、`targetSdk = 36`、`minSdk = flutter.minSdkVersion`（Flutter 3.38.7 当前为 24）。若产品上明确只支持 Android 8+，需显式写 `minSdk = 26`。
- Storage Access Framework：`file_picker` 默认走 SAF，无需额外申请存储权限。
- SQLite / FTS5：Android 系统自带的 SQLite **未编入 FTS5 模块**（只有 FTS3/4），直接建 FTS5 虚表会抛 `no such module: fts5`，曾导致数据库初始化失败、应用启动黑屏。解决：全平台统一经 `sqflite_common_ffi` 走 ffi，由 `sqlite3` v3 提供自带含 FTS5 的 SQLite（经 build hooks 打包进应用），不依赖系统库。
- 构建工具链、JDK 版本、签名与分发详见 [03-build-and-release.md](./03-build-and-release.md)。

### 6.2 macOS

- SQLite 初始化与 6.1 一致：全平台统一 ffi + 自带 `sqlite3`，macOS 无特殊处理。
- 沙盒：默认 enabled，需要在 `macos/Runner/*.entitlements` 中开启 `com.apple.security.files.user-selected.read-only` 才能选文件。
- 因为导入后会拷贝到 app 沙盒，不需要长期持有 security-scoped bookmark。

### 6.3 Windows

- SQLite 初始化与 6.1 一致：全平台统一 ffi + 自带 `sqlite3`。
- 构建依赖：Visual Studio 2022 + “Desktop development with C++” 工作负载。

### 6.4 Linux

- 同 Windows，需要 ffi 后端。
- 构建依赖：`clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`。

## 7. 状态管理约定

- 全局只读单例（数据库连接等）：用初始化后的单例或 Riverpod `Provider` 包装。
- 页面级异步状态（书架列表、当前阅读章节）：用 `AsyncNotifierProvider` / `AsyncNotifierProvider.family`。
- 生命周期短、重新进入应刷新数据库状态的页面：优先 `autoDispose`，例如 `readerProvider`。
- 纯 UI 局部状态允许 `StatefulWidget + setState`，例如阅读页菜单显隐；滚动进度这类高频刷新应使用 `ValueNotifier` 等局部监听，避免重建大正文。
- 跨页面共享但生命周期短的数据：避免常驻全局，宁可重新查询数据库。

## 8. 测试策略

- core/ 模块（编码检测、章节解析、数据库操作）：单元测试覆盖。
- features/ 模块：核心业务逻辑（importer、search、pagination、reader progress）单测。
- UI 层：MVP 阶段手工验证为主；重点覆盖导入、搜索跳转、书签跳转、翻页 / 滚动切换、字号 / 行距切换后位置保持。
- 提交前执行 `flutter analyze`，必须无 error。

## 9. 已识别的技术风险

| 风险 | 影响 | 应对 |
|---|---|---|
| Android 第一次构建踩 Gradle / NDK / JDK 版本 | 阻塞 | 已拆出 [03-build-and-release.md](./03-build-and-release.md)，按真实配置记录版本，不凭注释或最大值推断 |
| JDK 过新导致 Gradle / AGP 不兼容 | 阻塞构建 | 当前构建固定使用 JDK 17；不要为迁就 JDK 25 主动升级 Gradle / AGP |
| FTS5 索引体积较大 | 占用大 | MVP 接受；现自带 `sqlite3` 版本可控，远期可评估 contentless 模式 |
| 1 字符关键词搜不到 | 短词搜索失效 | 文档明确“≥2 字符”；如需 1 字搜索，再加 LIKE 兜底分支 |
| TextPainter 在不同平台字体度量微差 | 分页结果略不同 | 接受差异（同一设备稳定即可），不强求跨平台一致 |
| 滚动模式用比例映射字符偏移 | 恢复位置不如分页精确 | 作为连续滚动的近似进度；书签 / 搜索跳转仍以章节内字符偏移为源数据 |
| 大文件（>10MB）导入 / 分页 UI 卡顿 | 体验下降 | MVP 不优化；后续用 Isolate + 流式解析 |
| 动效过多导致低端设备掉帧 | 操作反馈变差 | 只做轻量入场动画；正文滚动区不做逐项动画 |
| GBK 文件少见字符解码失败 | 个别小说乱码 | 使用 GB18030 兼容路径；仍失败时提示并允许跳过 |

## 10. 编码与协作规范

- 关键步骤代码写**简洁的中文注释**：说明“为什么”，避免复述代码“做什么”。
- 模块化优先：通用数值放入 `app_tokens.dart`，避免散落硬编码。
- 阅读器和 UI 复杂度持续上升时，应优先拆 widget / service，避免单文件继续膨胀。
- 不主动生成总结性文档；若新增构建、发布、迁移等流程，放入 `docs/dev/` 并从本文档或 README 链接。
- 提交前 `flutter analyze` 必须无 error。
- 命名使用英文，避免中文标识符。
