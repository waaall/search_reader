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

  test('导航存在多层子章节时递归收集正文且同一 XHTML 只保留一次', () async {
    final epubPath = await _writeEpub(tempDirectory, {
      'META-INF/container.xml': _containerXml('OEBPS/book.opf'),
      'OEBPS/book.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>递归测试</dc:title></metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="root" href="root.xhtml" media-type="application/xhtml+xml"/>
    <item id="shared" href="shared.xhtml" media-type="application/xhtml+xml"/>
    <item id="tail" href="tail.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="root"/></spine>
</package>
''',
      'OEBPS/toc.ncx': '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="root"><navLabel><text>卷一</text></navLabel><content src="root.xhtml"/>
      <navPoint id="part1"><navLabel><text>第一节</text></navLabel><content src="shared.xhtml#part1"/></navPoint>
      <navPoint id="part2"><navLabel><text>第二节</text></navLabel><content src="shared.xhtml#part2"/></navPoint>
      <navPoint id="tail"><navLabel><text>尾章</text></navLabel><content src="tail.xhtml"/></navPoint>
    </navPoint>
  </navMap>
</ncx>
''',
      'OEBPS/root.xhtml': '<html><body><h1>卷一正文</h1><p>根内容</p></body></html>',
      'OEBPS/shared.xhtml':
          '<html><body><h2 id="part1">第一节</h2><p>共享内容 A</p><h2 id="part2">第二节</h2><p>共享内容 B</p></body></html>',
      'OEBPS/tail.xhtml': '<html><body><h1>尾章</h1><p>尾部内容</p></body></html>',
    });
    final outputPath = p.join(tempDirectory.path, 'recursive.txt');

    final manifest = await EpubParser().parseToFile(epubPath, outputPath);
    final content = await File(outputPath).readAsString();

    expect(manifest.chapters, hasLength(3));
    expect(manifest.chapters.map((chapter) => chapter.title), [
      '卷一',
      '第一节',
      '尾章',
    ]);
    expect(content, contains('共享内容 A'));
    expect(content, contains('共享内容 B'));
    expect('共享内容 A'.allMatches(content), hasLength(1));
    expect('共享内容 B'.allMatches(content), hasLength(1));
    expect(content.indexOf('根内容'), lessThan(content.indexOf('共享内容 A')));
    expect(content.indexOf('共享内容 B'), lessThan(content.indexOf('尾部内容')));
  });

  test('没有导航目录时按 spine 顺序导入全部正文', () async {
    final epubPath = await _writeEpub(tempDirectory, {
      'META-INF/container.xml': _containerXml('OPS/content.opf'),
      'OPS/content.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>无目录测试</dc:title></metadata>
  <manifest>
    <item id="first" href="text/first.xhtml" media-type="application/xhtml+xml"/>
    <item id="second" href="text/second.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="second"/>
    <itemref idref="first"/>
  </spine>
</package>
''',
      'OPS/text/first.xhtml':
          '<html><head><title>第一章</title></head><body><p>第一内容</p></body></html>',
      'OPS/text/second.xhtml':
          '<html><head><title>第二章</title></head><body><p>第二内容</p></body></html>',
    });
    final outputPath = p.join(tempDirectory.path, 'without_toc.txt');

    final manifest = await EpubParser().parseToFile(epubPath, outputPath);
    final parsed = await EpubParser().parse(epubPath);
    final content = await File(outputPath).readAsString();

    expect(manifest.chapters, hasLength(2));
    expect(manifest.chapters.map((chapter) => chapter.title), ['第二章', '第一章']);
    expect(content, isNot(contains('空书')));
    expect(content.indexOf('第二内容'), lessThan(content.indexOf('第一内容')));
    expect(parsed.fullText, content);
    expect(parsed.chapters, hasLength(2));
  });

  test('EPUB 3 的 nav 可递归读取，且导航文件不会当正文导入', () async {
    final epubPath = await _writeEpub(tempDirectory, {
      'META-INF/container.xml': _containerXml('OEBPS/package.opf'),
      'OEBPS/package.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>EPUB3 测试</dc:title></metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav scripted"/>
    <item id="one" href="text/one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="text/two.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="one"/><itemref idref="two"/></spine>
</package>
''',
      'OEBPS/nav.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body><nav epub:type="toc"><h2>目录</h2><ol>
    <li><a href="text/one.xhtml">第一章</a><ol>
      <li><a href="text/two.xhtml">第二章</a></li>
    </ol></li>
  </ol></nav></body>
</html>
''',
      'OEBPS/text/one.xhtml': '<html><body><p>EPUB3 第一内容</p></body></html>',
      'OEBPS/text/two.xhtml': '<html><body><p>EPUB3 第二内容</p></body></html>',
    });
    final outputPath = p.join(tempDirectory.path, 'epub3.txt');

    final manifest = await EpubParser().parseToFile(epubPath, outputPath);
    final content = await File(outputPath).readAsString();

    expect(manifest.chapters, hasLength(2));
    expect(manifest.chapters.map((chapter) => chapter.title), ['第一章', '第二章']);
    expect(content, contains('EPUB3 第一内容'));
    expect(content, contains('EPUB3 第二内容'));
    expect(content, isNot(contains('目录')));
  });

  test('spine 为空时扫描 manifest，仍能恢复全部文本文件', () async {
    final epubPath = await _writeEpub(tempDirectory, {
      'META-INF/container.xml': _containerXml('OEBPS/content.opf'),
      'OEBPS/content.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>manifest 测试</dc:title></metadata>
  <manifest>
    <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="two.xhtml" media-type="text/html"/>
  </manifest>
  <spine></spine>
</package>
''',
      'OEBPS/one.xhtml': '<html><body><p>manifest 第一部分</p></body></html>',
      'OEBPS/two.xhtml': '<html><body><p>manifest 第二部分</p></body></html>',
    });
    final outputPath = p.join(tempDirectory.path, 'manifest.txt');

    final manifest = await EpubParser().parseToFile(epubPath, outputPath);
    final content = await File(outputPath).readAsString();

    expect(manifest.chapters, hasLength(2));
    expect(content, contains('manifest 第一部分'));
    expect(content, contains('manifest 第二部分'));
  });

  test('导航损坏时不阻断正文，继续按 spine 兜底', () async {
    final epubPath = await _writeEpub(tempDirectory, {
      'META-INF/container.xml': _containerXml('OEBPS/content.opf'),
      'OEBPS/content.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>损坏目录测试</dc:title></metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="one"/><itemref idref="two"/></spine>
</package>
''',
      'OEBPS/toc.ncx': '<ncx><navMap>',
      'OEBPS/one.xhtml':
          '<html><body><h1>第一章</h1><p>损坏目录第一部分</p></body></html>',
      'OEBPS/two.xhtml':
          '<html><body><h1>第二章</h1><p>损坏目录第二部分</p></body></html>',
    });
    final outputPath = p.join(tempDirectory.path, 'broken_toc.txt');

    final manifest = await EpubParser().parseToFile(epubPath, outputPath);
    final content = await File(outputPath).readAsString();

    expect(manifest.chapters, hasLength(2));
    expect(content, contains('损坏目录第一部分'));
    expect(content, contains('损坏目录第二部分'));
  });

  test('NCX 相对路径和百分号编码路径可以定位正文', () async {
    final epubPath = await _writeEpub(tempDirectory, {
      'META-INF/container.xml': _containerXml('OEBPS/content.opf'),
      'OEBPS/content.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>路径测试</dc:title></metadata>
  <manifest>
    <item id="ncx" href="nav/toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="chapter" href="text/%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="chapter"/></spine>
</package>
''',
      'OEBPS/nav/toc.ncx': '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap><navPoint id="one"><navLabel><text>编码章节</text></navLabel>
    <content src="../text/%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml"/>
  </navPoint></navMap>
</ncx>
''',
      'OEBPS/text/第一章.xhtml': '<html><body><p>编码路径正文</p></body></html>',
    });
    final outputPath = p.join(tempDirectory.path, 'encoded_path.txt');

    final manifest = await EpubParser().parseToFile(epubPath, outputPath);
    final content = await File(outputPath).readAsString();

    expect(manifest.chapters, hasLength(1));
    expect(manifest.chapters.single.title, '编码章节');
    expect(content, contains('编码路径正文'));
  });
}

Future<String> _writeEpub(
  Directory directory,
  Map<String, String> files,
) async {
  final epubPath = p.join(directory.path, 'fixture.epub');
  final archive = Archive();
  archive.addFile(
    ArchiveFile.noCompress(
      'mimetype',
      'application/epub+zip'.length,
      utf8.encode('application/epub+zip'),
    ),
  );
  for (final entry in files.entries) {
    _addFile(archive, entry.key, entry.value);
  }
  await File(epubPath).writeAsBytes(ZipEncoder().encode(archive)!);
  return epubPath;
}

String _containerXml(String packagePath) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="$packagePath" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';

void _addFile(Archive archive, String path, String content) {
  final bytes = utf8.encode(content);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}
