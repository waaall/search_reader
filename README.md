# search_reader

本地小说阅读器。目标是把 txt / epub 小说导入到本机沙盒中，提供书架、阅读进度、全文搜索、书签和可调阅读体验；所有书籍与索引都保存在本地，不依赖云端服务。

## 当前能力

- 导入本地 txt / epub 文件，并复制到应用沙盒。
- 自动识别常见中文文本编码：UTF-8、UTF-16、GBK / GB18030。
- 按章节解析小说；未识别章节时整本书作为单章节。
- 书架按最近阅读排序，支持导入进度与错误提示。
- 阅读页支持两种阅读模式：
  - **翻页模式**：基于 `TextPainter` 按字号、行距和屏幕尺寸分页。
  - **滚动模式**：连续滑动阅读，停止滚动后保存进度。
- 阅读设置：字号、行距、日间 / 夜间 / 护眼主题、翻页 / 滚动模式。
- 阅读进度持久化；重新进入阅读页时恢复到上次位置。
- 书签：阅读页添加、目录 / 书签抽屉查看、全局书签页查看与删除。
- 全文搜索：SQLite FTS5 + Dart 侧 bigram 索引，支持 2 字及以上中文关键词；搜索结果可跳转到对应章节位置。
- App 外层主题使用 `flex_color_scheme`，统一 Material 组件圆角与交互效果。
- 书架、搜索、书签等页面使用轻量入场动效；正文滚动区避免高频重建。

## 技术栈

- Flutter 3.x / Dart 3.x
- Riverpod 2.x
- SQLite：`sqflite` + `sqflite_common_ffi`
- FTS5：`unicode61` + Dart bigram token
- 文件与路径：`file_picker`、`path_provider`、`path`
- 文本与书籍解析：`enough_convert`、`epubx`、`html`、`archive`
- 主题与动效：`flex_color_scheme`、`flutter_animate`

## 文档

- 产品需求：[`docs/demand/01-product-requirements.md`](docs/demand/01-product-requirements.md)
- 技术设计：[`docs/dev/02-technical-design.md`](docs/dev/02-technical-design.md)
- 构建与分发：[`docs/dev/03-build-and-release.md`](docs/dev/03-build-and-release.md)

## 本地开发

```bash
flutter pub get
flutter run
```

常用检查：

```bash
flutter analyze
flutter test
```

## 构建

Android / macOS 已有详细工具链说明，见 [`docs/dev/03-build-and-release.md`](docs/dev/03-build-and-release.md)。环境配置完成后常用命令：

```bash
flutter build apk      # Android APK
flutter build macos    # macOS .app
```

> 当前 Android release 构建仍使用 debug 签名，适合自用或小范围分发；正式上架前需要替换为 release keystore。

## 数据与隐私

- 书籍文件复制到应用文档目录下的 `books/` 子目录。
- 数据库文件为 `search_reader.db`，保存书籍元数据、章节、索引、阅读进度、设置与书签。
- 全文索引和阅读数据只保存在本机。
