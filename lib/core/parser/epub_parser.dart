import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import 'book_format.dart';

// epub 章节解析：按顶层 Chapters 顺序，每章 HTML 抽成纯文本拼成 fullText
// MVP 策略：忽略 SubChapters（避免与父章节 HtmlContent 内容重复）
//   - 大部分中文小说 epub 章节是平铺的，足够覆盖
//   - 图片 / 样式 / 字体均丢弃，reader 只渲染纯文本
// epub 解析失败时抛出，带可读的错误原因；ImporterService 会进一步包装
class EpubParseException implements Exception {
  final String message;
  EpubParseException(this.message);
  @override
  String toString() => message;
}

class EpubParser implements BookFormatParser {
  @override
  Future<ParsedBook> parse(String filePath) async {
    // epub 来源两种：标准 zip 文件 / 解压后的目录
    // 一些下载渠道把 epub 以解压目录形式提供（Finder 直接显示为文件夹），
    // 这里现场打包成 zip 字节流再喂给 epubx，对用户透明
    final List<int> bytes;
    try {
      bytes = await _readEpubBytes(filePath);
    } on EpubParseException {
      rethrow;
    } catch (e) {
      throw EpubParseException('读取 epub 文件失败：$e');
    }

    // epubx + archive 内部可能抛 ArgumentError / FormatException / StateError
    // 一律翻译成 EpubParseException 让上层 UI 能展示有效信息
    final EpubBook book;
    try {
      book = await EpubReader.readBook(bytes);
    } catch (e) {
      throw EpubParseException('epub 解析失败（可能文件损坏或非标准格式）：$e');
    }

    final rawChapters = book.Chapters ?? const <EpubChapter>[];
    final buffer = StringBuffer();
    final result = <ParsedChapter>[];

    for (var i = 0; i < rawChapters.length; i++) {
      final c = rawChapters[i];
      final title = _normalizeTitle(c.Title, fallbackIndex: i);
      final content = _htmlToPlainText(c.HtmlContent ?? '');
      // 章节之间用空行分隔，避免上一章末尾与下一章标题粘连
      if (buffer.isNotEmpty) buffer.write('\n\n');

      final startChar = buffer.length;
      // 把章节标题作为正文第一行写入，方便用户阅读 + FTS 搜索章节标题
      buffer.write(title);
      buffer.write('\n\n');
      buffer.write(content);
      final endChar = buffer.length;

      result.add(ParsedChapter(
        title: title,
        startChar: startChar,
        endChar: endChar,
        content: buffer.toString().substring(startChar, endChar),
      ));
    }

    // 全空 epub 兜底：保留一个占位章节，避免下游空表崩溃
    if (result.isEmpty) {
      buffer.write('（空书）');
      result.add(ParsedChapter(
        title: '正文',
        startChar: 0,
        endChar: buffer.length,
        content: buffer.toString(),
      ));
    }

    return ParsedBook(
      fullText: buffer.toString(),
      chapters: result,
      encoding: 'utf-8',
    );
  }

  // 标题归一化：去空白、压缩连续空白；空标题用序号兜底
  String _normalizeTitle(String? raw, {required int fallbackIndex}) {
    final t = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return '第 ${fallbackIndex + 1} 章';
    return t;
  }

  // HTML → 纯文本：用 html 包解析 DOM，在块级元素后插入换行避免段落粘连
  // 不用正则去标签：嵌套结构与 HTML 实体（&nbsp; &amp; 等）正则处理不可靠
  static const _blockTags = {
    'p', 'div', 'br',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'tr', 'blockquote', 'pre',
  };

  String _htmlToPlainText(String html) {
    if (html.trim().isEmpty) return '';
    final doc = html_parser.parse(html);
    // 在块级元素末尾追加换行节点；toList() 防止边遍历边修改
    for (final el in doc.querySelectorAll('*').toList()) {
      if (_blockTags.contains(el.localName)) {
        el.append(html_dom.Text('\n'));
      }
    }
    final raw = doc.body?.text ?? doc.documentElement?.text ?? '';
    // 收敛多余空行：3+ 连续换行 → 2 个（保留段落分隔）
    return raw.replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  // 取得 epub 的 zip 字节流：文件直接读；目录则现场打包
  Future<List<int>> _readEpubBytes(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.file) {
      return await File(path).readAsBytes();
    }
    if (type == FileSystemEntityType.directory) {
      return await _packDirectoryAsZip(path);
    }
    throw EpubParseException('路径不存在或类型未知：$path');
  }

  // 把已解压的 epub 目录打包成 epub 规范的 zip 字节流
  // epub 规范：mimetype 必须是 zip 中第一个 entry，且不压缩（STORE）
  Future<List<int>> _packDirectoryAsZip(String dirPath) async {
    final dir = Directory(dirPath);
    final archive = Archive();

    // 1) mimetype 优先入档，STORE 不压缩
    final mimetypeFile = File(p.join(dirPath, 'mimetype'));
    if (await mimetypeFile.exists()) {
      final bytes = await mimetypeFile.readAsBytes();
      final entry = ArchiveFile('mimetype', bytes.length, bytes);
      entry.compress = false;
      archive.addFile(entry);
    }

    // 2) 其余文件递归入档，跳过 macOS / 系统元数据
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relPath = p.relative(entity.path, from: dirPath).replaceAll('\\', '/');
      if (relPath == 'mimetype') continue; // 已加
      if (relPath.endsWith('/.DS_Store') || relPath == '.DS_Store') continue;
      if (relPath.startsWith('__MACOSX/')) continue;

      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null || zipBytes.isEmpty) {
      throw EpubParseException('无法把 epub 目录打包成 zip 流');
    }
    return zipBytes;
  }
}
