// EPUB 解析回归测试：验证只提取章节正文，并能生成规范化字节范围。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:search_reader/core/parser/epub_parser.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('epub_streaming_');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('只读取章节 HTML，不加载 EPUB 图片资源', () async {
    final epubPath = p.join(tempDirectory.path, 'book.epub');
    final outputPath = p.join(tempDirectory.path, 'book.txt');
    final archive = Archive();
    archive.addFile(
      ArchiveFile.noCompress(
        'mimetype',
        'application/epub+zip'.length,
        utf8.encode('application/epub+zip'),
      ),
    );
    _addFile(archive, 'META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''');
    _addFile(archive, 'OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书</dc:title><dc:language>zh</dc:language><dc:identifier id="bookid">id</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="chapter.xhtml" media-type="application/xhtml+xml"/>
    <item id="image" href="cover.bin" media-type="image/png"/>
  </manifest>
  <spine toc="ncx"><itemref idref="ch1"/></spine>
</package>
''');
    _addFile(archive, 'OEBPS/toc.ncx', '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="id"/></head>
  <docTitle><text>测试书</text></docTitle>
  <navMap>
    <navPoint id="p1" playOrder="1"><navLabel><text>第一章</text></navLabel><content src="chapter.xhtml"/></navPoint>
  </navMap>
</ncx>
''');
    _addFile(
      archive,
      'OEBPS/chapter.xhtml',
      '<html><body><h1>第一章</h1><p>你好世界</p></body></html>',
    );
    _addFile(archive, 'OEBPS/cover.bin', 'x' * 1024 * 1024);
    await File(epubPath).writeAsBytes(ZipEncoder().encode(archive)!);

    final manifest = await EpubParser().parseToFile(epubPath, outputPath);
    final content = await File(outputPath).readAsString();

    expect(manifest.chapters, hasLength(1));
    expect(content, contains('第一章'));
    expect(content, contains('你好世界'));
    expect(manifest.totalBytes, utf8.encode(content).length);
    expect(
      utf8.decode(
        utf8
            .encode(content)
            .sublist(
              manifest.chapters.single.startByte,
              manifest.chapters.single.endByte,
            ),
      ),
      content,
    );
  });
}

void _addFile(Archive archive, String path, String content) {
  final bytes = utf8.encode(content);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}
