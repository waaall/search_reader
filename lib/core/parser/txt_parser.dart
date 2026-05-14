import 'dart:io';

import '../encoding/text_decoder.dart';
import 'book_format.dart';

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

  // 文本归一化：统一换行，去掉 BOM 残留
  String _normalize(String text) {
    var s = text;
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
      s = s.substring(1);
    }
    return s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  // 切章节：用正则在原文中找所有标题位置，相邻标题之间为一章
  List<ParsedChapter> _splitChapters(String text) {
    final matches = _chapterPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      // 没识别到任何章节 → 整本书一个章节
      return [
        ParsedChapter(
          title: '正文',
          startChar: 0,
          endChar: text.length,
          content: text,
        ),
      ];
    }

    // 第一个标题之前的文本视为前言（如有）
    final result = <ParsedChapter>[];
    if (matches.first.start > 0) {
      final preface = text.substring(0, matches.first.start).trim();
      if (preface.isNotEmpty) {
        result.add(ParsedChapter(
          title: '前言',
          startChar: 0,
          endChar: matches.first.start,
          content: preface,
        ));
      }
    }

    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final rawTitle = text
          .substring(matches[i].start, matches[i].end)
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
      final content = text.substring(start, end);
      result.add(ParsedChapter(
        title: rawTitle,
        startChar: start,
        endChar: end,
        content: content,
      ));
    }
    return result;
  }
}
