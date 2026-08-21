// 导入资源上限：集中约束输入文件、解压目录和正文产物，避免限制散落在各层。

class ImportLimits {
  static const defaultMaxTxtBytes = 10 * 1024 * 1024;
  // 当前阅读器只提取 EPUB 正文，默认将打包文件大小限制为 10 MiB。
  static const defaultMaxEpubBytes = 10 * 1024 * 1024;
  static const defaultMaxEpubDirectoryEntries = 10000;
  static const defaultMaxEpubDirectoryBytes = 200 * 1024 * 1024;
  static const defaultMaxEpubChapterSourceBytes = 16 * 1024 * 1024;
  static const defaultMaxTextChars = 20 * 1024 * 1024;
  static const defaults = ImportLimits();

  const ImportLimits({
    this.maxTxtBytes = defaultMaxTxtBytes,
    this.maxEpubBytes = defaultMaxEpubBytes,
    this.maxEpubDirectoryEntries = defaultMaxEpubDirectoryEntries,
    this.maxEpubDirectoryBytes = defaultMaxEpubDirectoryBytes,
    this.maxEpubChapterSourceBytes = defaultMaxEpubChapterSourceBytes,
    this.maxTextChars = defaultMaxTextChars,
  });

  // 维持现有产品限制，同时为解压内容和最终正文增加独立保护。
  final int maxTxtBytes;
  final int maxEpubBytes;
  final int maxEpubDirectoryEntries;
  final int maxEpubDirectoryBytes;
  final int maxEpubChapterSourceBytes;
  final int maxTextChars;

  int limitForExtension(String extension) {
    return extension.toLowerCase() == '.epub' ? maxEpubBytes : maxTxtBytes;
  }

  Map<String, Object?> toMap() => {
    'maxTxtBytes': maxTxtBytes,
    'maxEpubBytes': maxEpubBytes,
    'maxEpubDirectoryEntries': maxEpubDirectoryEntries,
    'maxEpubDirectoryBytes': maxEpubDirectoryBytes,
    'maxEpubChapterSourceBytes': maxEpubChapterSourceBytes,
    'maxTextChars': maxTextChars,
  };

  factory ImportLimits.fromMap(Map<Object?, Object?> map) {
    final fallback = ImportLimits.defaults;
    int read(String key, int fallback) =>
        map[key] is int ? map[key]! as int : fallback;

    return ImportLimits(
      maxTxtBytes: read('maxTxtBytes', fallback.maxTxtBytes),
      maxEpubBytes: read('maxEpubBytes', fallback.maxEpubBytes),
      maxEpubDirectoryEntries: read(
        'maxEpubDirectoryEntries',
        fallback.maxEpubDirectoryEntries,
      ),
      maxEpubDirectoryBytes: read(
        'maxEpubDirectoryBytes',
        fallback.maxEpubDirectoryBytes,
      ),
      maxEpubChapterSourceBytes: read(
        'maxEpubChapterSourceBytes',
        fallback.maxEpubChapterSourceBytes,
      ),
      maxTextChars: read('maxTextChars', fallback.maxTextChars),
    );
  }
}
