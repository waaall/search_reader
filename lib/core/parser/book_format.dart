// 书籍格式解析抽象：txt 当前实现，epub 未来扩展
//
// 设计原则：上层（importer/reader/search）只依赖此接口，不感知具体格式

class ParsedChapter {
  final String title;
  final int startChar; // 在原文中的起始字符位置（含）
  final int endChar; // 在原文中的结束字符位置（不含）
  final String content; // 章节正文（用于建索引，导入完后可丢弃）

  const ParsedChapter({
    required this.title,
    required this.startChar,
    required this.endChar,
    required this.content,
  });
}

class ParsedBook {
  final String fullText;
  final List<ParsedChapter> chapters;
  final String encoding;

  const ParsedBook({
    required this.fullText,
    required this.chapters,
    required this.encoding,
  });

  int get totalChars => fullText.length;
}

abstract class BookFormatParser {
  // 解析整本书
  Future<ParsedBook> parse(String filePath);
}
