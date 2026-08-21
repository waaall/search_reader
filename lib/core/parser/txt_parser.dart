import 'dart:io';

import '../encoding/text_decoder.dart';
import 'book_format.dart';
import 'import_limits.dart';
import 'normalized_text_writer.dart';

// txt 章节标题正则：覆盖中文小说常见模式
// - 第X章/节/回/部/卷（X 支持中文数字与阿拉伯数字）
// - 序章/序言/序幕/楔子/引子/尾声/后记/前言
// - Chapter X（英文兼容）
// 行首允许半角空格、全角空格、制表符；标题整行长度限制在 ~40 字以内
final RegExp _chapterPattern = RegExp(
  r'^[ \t　]*('
  r'第[零〇一二三四五六七八九十百千万0-9]+[章节回部卷篇]'
  r'|序[章言幕]|楔子|引子|尾声|后记|前言|外传|番外'
  r'|Chapter\s+\d+'
  r')[^\r\n]{0,40}$',
  multiLine: true,
);

class TxtParser implements BookFormatParser {
  @override
  Future<ParsedBook> parse(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final decoded = TextDecoder.decode(bytes);
    final fullText = _normalize(decoded.content);

    final chapters = _splitChapters(fullText);
    return ParsedBook(
      fullText: fullText,
      chapters: chapters,
      encoding: decoded.encoding,
    );
  }

  // 在 worker 中把 TXT 解码、规范化并写成 UTF-8，同时只返回章节范围。
  Future<BookImportManifest> parseToFile(
    String inputPath,
    String outputPath, {
    ImportLimits limits = ImportLimits.defaults,
  }) async {
    final source = File(inputPath);
    final sourceLength = await source.length();
    if (sourceLength > limits.maxTxtBytes) {
      throw TxtParseException(
        'TXT 文件超过允许大小：$sourceLength > ${limits.maxTxtBytes}',
      );
    }

    final bytes = await source.readAsBytes();
    final decoded = TextDecoder.decode(bytes);
    final fullText = _normalize(decoded.content);
    _checkTextLimit(fullText, limits);

    final spans = splitChapterSpans(fullText);
    final writer = await NormalizedTextWriter.open(outputPath);
    final descriptors = <ChapterDescriptor>[];
    try {
      var cursorChar = 0;
      for (final span in spans) {
        // 章节识别可能忽略首尾空白，写文件时仍须保留原始规范化正文。
        if (span.startChar > cursorChar) {
          await _writeTextRange(writer, fullText, cursorChar, span.startChar);
        }
        final startChar = writer.charCount;
        final startByte = writer.byteCount;
        await _writeTextRange(writer, fullText, span.startChar, span.endChar);
        descriptors.add(
          ChapterDescriptor(
            title: span.title,
            startChar: startChar,
            endChar: writer.charCount,
            startByte: startByte,
            endByte: writer.byteCount,
          ),
        );
        cursorChar = span.endChar;
      }
      if (cursorChar < fullText.length) {
        await _writeTextRange(writer, fullText, cursorChar, fullText.length);
      }
      await writer.flushAndClose();
    } catch (_) {
      await writer.close();
      rethrow;
    }

    return BookImportManifest(
      chapters: descriptors,
      encoding: decoded.encoding,
      totalChars: writer.charCount,
      totalBytes: writer.byteCount,
    );
  }

  // 文本归一化：统一换行，去掉 BOM 残留
  String _normalize(String text) {
    var s = text;
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
      s = s.substring(1);
    }
    return s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  // 切章节：用正则在原文中找所有标题位置，相邻标题之间为一章
  List<ParsedChapter> _chaptersFromSpans(
    String text,
    List<TextChapterSpan> spans,
  ) {
    return spans
        .map(
          (span) => ParsedChapter(
            title: span.title,
            startChar: span.startChar,
            endChar: span.endChar,
            content: span.trimContent
                ? text.substring(span.startChar, span.endChar).trim()
                : text.substring(span.startChar, span.endChar),
          ),
        )
        .toList(growable: false);
  }

  // 只计算章节范围，供普通解析和流式导入共同使用。
  List<TextChapterSpan> splitChapterSpans(String text) {
    final matches = _chapterPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      // 没识别到任何章节 → 整本书一个章节
      return [TextChapterSpan(title: '正文', startChar: 0, endChar: text.length)];
    }

    // 第一个标题之前的文本视为前言（如有）
    final result = <TextChapterSpan>[];
    if (matches.first.start > 0) {
      final preface = text.substring(0, matches.first.start).trim();
      if (preface.isNotEmpty) {
        result.add(
          TextChapterSpan(
            title: '前言',
            startChar: 0,
            endChar: matches.first.start,
            trimContent: true,
          ),
        );
      }
    }

    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final rawTitle = text
          .substring(matches[i].start, matches[i].end)
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
      result.add(
        TextChapterSpan(title: rawTitle, startChar: start, endChar: end),
      );
    }
    return result;
  }

  List<ParsedChapter> _splitChapters(String text) {
    return _chaptersFromSpans(text, splitChapterSpans(text));
  }

  Future<void> _writeTextRange(
    NormalizedTextWriter writer,
    String text,
    int start,
    int end,
  ) async {
    const chunkChars = 64 * 1024;
    var offset = start;
    while (offset < end) {
      var chunkEnd = (offset + chunkChars).clamp(offset, end);
      // 不在 UTF-16 代理对中间切块，否则两次 UTF-8 编码会产生替换字符。
      if (chunkEnd < end &&
          chunkEnd > offset &&
          _isHighSurrogate(text.codeUnitAt(chunkEnd - 1)) &&
          _isLowSurrogate(text.codeUnitAt(chunkEnd))) {
        chunkEnd--;
      }
      await writer.write(text.substring(offset, chunkEnd));
      offset = chunkEnd;
    }
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  void _checkTextLimit(String text, ImportLimits limits) {
    if (text.length > limits.maxTextChars) {
      throw TxtParseException(
        '规范化正文超过允许长度：${text.length} > ${limits.maxTextChars}',
      );
    }
  }
}

class TextChapterSpan {
  final String title;
  final int startChar;
  final int endChar;
  final bool trimContent;

  const TextChapterSpan({
    required this.title,
    required this.startChar,
    required this.endChar,
    this.trimContent = false,
  });
}

class TxtParseException implements Exception {
  final String message;

  const TxtParseException(this.message);

  @override
  String toString() => message;
}
