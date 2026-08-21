// EPUB 解析器：只读取章节 HTML，忽略图片、字体等阅读器不需要的二进制资源。
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import 'book_format.dart';
import 'import_limits.dart';
import 'normalized_text_writer.dart';

class EpubParseException implements Exception {
  final String message;

  EpubParseException(this.message);

  @override
  String toString() => message;
}

class EpubParser implements BookFormatParser {
  @override
  Future<ParsedBook> parse(String filePath) async {
    final bytes = await _readEpubBytes(filePath, limits: ImportLimits.defaults);
    try {
      // openBook 只建立 EPUB 目录和章节引用，不读取图片、字体和所有正文。
      final book = await EpubReader.openBook(bytes);
      final rawChapters = await book.getChapters();
      final buffer = StringBuffer();
      final result = <ParsedChapter>[];

      for (var i = 0; i < rawChapters.length; i++) {
        final chapter = rawChapters[i];
        final title = _normalizeTitle(chapter.Title, fallbackIndex: i);
        final content = await _readChapterText(chapter);
        if (buffer.isNotEmpty) buffer.write('\n\n');

        final startChar = buffer.length;
        buffer.write(title);
        buffer.write('\n\n');
        buffer.write(content);
        final endChar = buffer.length;
        result.add(
          ParsedChapter(
            title: title,
            startChar: startChar,
            endChar: endChar,
            content: '$title\n\n$content',
          ),
        );
      }

      if (result.isEmpty) {
        buffer.write('（空书）');
        result.add(
          ParsedChapter(
            title: '正文',
            startChar: 0,
            endChar: buffer.length,
            content: buffer.toString(),
          ),
        );
      }

      return ParsedBook(
        fullText: buffer.toString(),
        chapters: result,
        encoding: 'utf-8',
      );
    } catch (e) {
      if (e is EpubParseException) rethrow;
      throw EpubParseException('EPUB 解析失败，文件可能损坏或格式不兼容：$e');
    }
  }

  // 解析并直接写入规范化正文文件，主 isolate 只接收章节范围。
  Future<BookImportManifest> parseToFile(
    String inputPath,
    String outputPath, {
    ImportLimits limits = ImportLimits.defaults,
  }) async {
    final bytes = await _readEpubBytes(inputPath, limits: limits);
    final writer = await NormalizedTextWriter.open(outputPath);
    var closed = false;
    try {
      final book = await EpubReader.openBook(bytes);
      final rawChapters = await book.getChapters();
      final descriptors = <ChapterDescriptor>[];

      for (var i = 0; i < rawChapters.length; i++) {
        final chapter = rawChapters[i];
        _checkChapterSourceSize(chapter, limits);
        final title = _normalizeTitle(chapter.Title, fallbackIndex: i);
        final content = await _readChapterText(chapter);

        if (writer.charCount > 0) await writer.write('\n\n');
        final startChar = writer.charCount;
        final startByte = writer.byteCount;
        await writer.write(title);
        await writer.write('\n\n');
        await writer.write(content);
        _checkTextLimit(writer.charCount, limits);
        descriptors.add(
          ChapterDescriptor(
            title: title,
            startChar: startChar,
            endChar: writer.charCount,
            startByte: startByte,
            endByte: writer.byteCount,
          ),
        );
      }

      if (descriptors.isEmpty) {
        final startChar = writer.charCount;
        final startByte = writer.byteCount;
        await writer.write('（空书）');
        descriptors.add(
          ChapterDescriptor(
            title: '正文',
            startChar: startChar,
            endChar: writer.charCount,
            startByte: startByte,
            endByte: writer.byteCount,
          ),
        );
      }

      await writer.flushAndClose();
      closed = true;
      return BookImportManifest(
        chapters: descriptors,
        encoding: 'utf-8',
        totalChars: writer.charCount,
        totalBytes: writer.byteCount,
      );
    } catch (e) {
      if (!closed) await writer.close();
      if (e is EpubParseException) rethrow;
      throw EpubParseException('EPUB 正文提取失败：$e');
    }
  }

  String _normalizeTitle(String? raw, {required int fallbackIndex}) {
    final title = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (title.isEmpty) return '第 ${fallbackIndex + 1} 章';
    return title;
  }

  static const _blockTags = {
    'p',
    'div',
    'br',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'tr',
    'blockquote',
    'pre',
  };

  String _htmlToPlainText(String html) {
    if (html.trim().isEmpty) return '';
    final doc = html_parser.parse(html);
    for (final element in doc.querySelectorAll('*').toList()) {
      if (_blockTags.contains(element.localName)) {
        element.append(html_dom.Text('\n'));
      }
    }
    final raw = doc.body?.text ?? doc.documentElement?.text ?? '';
    return raw
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<String> _readChapterText(EpubChapterRef chapter) async {
    try {
      return _htmlToPlainText(await chapter.readHtmlContent());
    } catch (e) {
      throw EpubParseException('读取 EPUB 章节失败：$e');
    }
  }

  void _checkChapterSourceSize(EpubChapterRef chapter, ImportLimits limits) {
    final size = chapter.epubTextContentFileRef?.getContentFileEntry().size;
    if (size != null && size > limits.maxEpubChapterSourceBytes) {
      throw EpubParseException(
        'EPUB 单章源文件超过允许大小：$size > ${limits.maxEpubChapterSourceBytes}',
      );
    }
  }

  void _checkTextLimit(int chars, ImportLimits limits) {
    if (chars > limits.maxTextChars) {
      throw EpubParseException(
        'EPUB 规范化正文超过允许长度：$chars > ${limits.maxTextChars}',
      );
    }
  }

  // 文件型 EPUB 直接读取；目录型 EPUB 先流式打包，避免把每个资源同时读入内存。
  Future<List<int>> _readEpubBytes(
    String path, {
    required ImportLimits limits,
  }) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.file) {
      final file = File(path);
      final length = await file.length();
      if (length > limits.maxEpubBytes) {
        throw EpubParseException(
          'EPUB 文件超过允许大小：$length > ${limits.maxEpubBytes}',
        );
      }
      return file.readAsBytes();
    }
    if (type == FileSystemEntityType.directory) {
      return _packDirectoryAsZip(path, limits: limits);
    }
    throw EpubParseException('EPUB 路径不存在或类型不受支持：$path');
  }

  Future<List<int>> _packDirectoryAsZip(
    String dirPath, {
    required ImportLimits limits,
  }) async {
    final files = <File>[];
    var totalBytes = 0;
    await for (final entity in Directory(
      dirPath,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: dirPath)
          .replaceAll('\\', '/');
      if (relative == '.DS_Store' ||
          relative.endsWith('/.DS_Store') ||
          relative.startsWith('__MACOSX/')) {
        continue;
      }
      files.add(entity);
      totalBytes += await entity.length();
      if (files.length > limits.maxEpubDirectoryEntries ||
          totalBytes > limits.maxEpubDirectoryBytes) {
        throw EpubParseException('解压 EPUB 目录超过资源上限');
      }
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'search_reader_epub_',
    );
    final zipPath = p.join(tempDir.path, 'book.epub');
    final encoder = ZipFileEncoder();
    var encoderClosed = false;
    try {
      encoder.open(zipPath);
      final mimetype = File(p.join(dirPath, 'mimetype'));
      if (await mimetype.exists()) {
        final content = await mimetype.readAsBytes();
        encoder.addArchiveFile(
          ArchiveFile.noCompress('mimetype', content.length, content),
        );
      }

      files.sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final relative = p
            .relative(file.path, from: dirPath)
            .replaceAll('\\', '/');
        if (relative == 'mimetype') continue;
        await encoder.addFile(file, relative, ZipFileEncoder.GZIP);
      }
      await encoder.close();
      encoderClosed = true;

      final zipped = File(zipPath);
      final length = await zipped.length();
      if (length > limits.maxEpubBytes) {
        throw EpubParseException(
          '打包后的 EPUB 超过允许大小：$length > ${limits.maxEpubBytes}',
        );
      }
      return zipped.readAsBytes();
    } finally {
      if (!encoderClosed) {
        try {
          await encoder.close();
        } catch (_) {}
      }
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
