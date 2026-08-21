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

// 已写入规范化正文文件的章节范围；正文本身不跨 isolate 传回主 isolate。
class ChapterDescriptor {
  final String title;
  final int startChar;
  final int endChar;
  final int startByte;
  final int endByte;

  const ChapterDescriptor({
    required this.title,
    required this.startChar,
    required this.endChar,
    required this.startByte,
    required this.endByte,
  });

  Map<String, Object?> toMap() => {
    'title': title,
    'startChar': startChar,
    'endChar': endChar,
    'startByte': startByte,
    'endByte': endByte,
  };

  factory ChapterDescriptor.fromMap(Map<Object?, Object?> map) {
    return ChapterDescriptor(
      title: map['title']! as String,
      startChar: map['startChar']! as int,
      endChar: map['endChar']! as int,
      startByte: map['startByte']! as int,
      endByte: map['endByte']! as int,
    );
  }
}

// 导入 worker 的小型返回值：只保存章节元数据和全文统计，不保存正文副本。
class BookImportManifest {
  final List<ChapterDescriptor> chapters;
  final String encoding;
  final int totalChars;
  final int totalBytes;

  const BookImportManifest({
    required this.chapters,
    required this.encoding,
    required this.totalChars,
    required this.totalBytes,
  });

  Map<String, Object?> toMap() => {
    'chapters': chapters.map((chapter) => chapter.toMap()).toList(),
    'encoding': encoding,
    'totalChars': totalChars,
    'totalBytes': totalBytes,
  };

  factory BookImportManifest.fromMap(Map<Object?, Object?> map) {
    final rawChapters = map['chapters']! as List<Object?>;
    return BookImportManifest(
      chapters: rawChapters
          .map(
            (chapter) =>
                ChapterDescriptor.fromMap(chapter! as Map<Object?, Object?>),
          )
          .toList(growable: false),
      encoding: map['encoding']! as String,
      totalChars: map['totalChars']! as int,
      totalBytes: map['totalBytes']! as int,
    );
  }
}

abstract class BookFormatParser {
  // 解析整本书
  Future<ParsedBook> parse(String filePath);
}
