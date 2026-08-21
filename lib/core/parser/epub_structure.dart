// EPUB 结构读取：优先使用 spine 保证正文覆盖，导航只用于补充顺序和标题。
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class EpubChapterSource {
  final ArchiveFile file;
  final String? navigationTitle;

  const EpubChapterSource({required this.file, required this.navigationTitle});
}

class EpubStructureReader {
  const EpubStructureReader();

  static const _textMediaTypes = {
    'application/xhtml+xml',
    'text/html',
    'text/x-oeb1-document',
    'application/x-dtbook+xml',
    'application/xml',
  };

  List<EpubChapterSource> read(Archive archive) {
    final packagePath = _readPackagePath(archive);
    final packageFile = _findArchiveFile(archive, packagePath);
    if (packageFile == null) {
      throw const FormatException('EPUB 根文件不存在');
    }

    final packageDocument = _parseXml(packageFile, 'EPUB OPF');
    final packageDirectory = _zipDirectory(packageFile.name);
    final manifest = _readManifest(archive, packageDocument, packageDirectory);
    if (manifest.isEmpty) {
      throw const FormatException('EPUB manifest 为空');
    }

    final manifestById = <String, _ManifestItem>{
      for (final item in manifest)
        if (item.id.isNotEmpty) item.id: item,
    };
    final spine = _readSpine(packageDocument);
    final navigation = _readNavigation(archive, manifest, manifestById, spine);
    final navigationTitles = <String, String>{};
    for (final target in navigation) {
      final title = target.title?.trim();
      if (title == null || title.isEmpty) continue;
      navigationTitles.putIfAbsent(target.path, () => title);
    }

    final orderedItems = <_ManifestItem>[];
    final seenPaths = <String>{};

    void addItem(_ManifestItem? item) {
      final file = item?.file;
      if (item == null || file == null || !_isTextItem(item)) return;
      if (seenPaths.add(file.name)) orderedItems.add(item);
    }

    // spine 是正文的主顺序；即使导航目录缺失，也不影响正文导入。
    for (final idRef in spine.idRefs) {
      addItem(manifestById[idRef]);
    }

    // spine 不完整时，用递归导航补齐被目录引用的正文文件。
    for (final target in navigation) {
      addItem(_findManifestByPath(manifest, target.path));
    }

    // 两者都不完整时，最后扫描 manifest，优先保证全文不丢失。
    for (final item in manifest) {
      addItem(item);
    }

    if (orderedItems.isEmpty) {
      return const [];
    }

    return orderedItems
        .map(
          (item) => EpubChapterSource(
            file: item.file!,
            navigationTitle: navigationTitles[item.file!.name],
          ),
        )
        .toList(growable: false);
  }

  List<_ManifestItem> _readManifest(
    Archive archive,
    XmlDocument packageDocument,
    String packageDirectory,
  ) {
    final manifestElement = _firstDescendant(packageDocument, 'manifest');
    if (manifestElement == null) return const [];

    final result = <_ManifestItem>[];
    for (final itemElement in _children(manifestElement, 'item')) {
      final id = _attribute(itemElement, 'id');
      final href = _attribute(itemElement, 'href');
      final mediaType = _attribute(itemElement, 'media-type');
      if (id == null || href == null || mediaType == null) continue;

      result.add(
        _ManifestItem(
          id: id,
          mediaType: mediaType,
          properties: _attribute(itemElement, 'properties'),
          file: _resolveArchiveFile(archive, packageDirectory, href),
        ),
      );
    }
    return result;
  }

  _SpineData _readSpine(XmlDocument packageDocument) {
    final spineElement = _firstDescendant(packageDocument, 'spine');
    if (spineElement == null) return const _SpineData();

    final idRefs = <String>[];
    for (final itemRef in _children(spineElement, 'itemref')) {
      final idRef = _attribute(itemRef, 'idref');
      if (idRef != null && idRef.isNotEmpty) idRefs.add(idRef);
    }
    return _SpineData(
      idRefs: idRefs,
      tableOfContentsId: _attribute(spineElement, 'toc'),
    );
  }

  List<_NavigationTarget> _readNavigation(
    Archive archive,
    List<_ManifestItem> manifest,
    Map<String, _ManifestItem> manifestById,
    _SpineData spine,
  ) {
    _ManifestItem? navFile;
    for (final item in manifest) {
      if (item.file != null && _hasToken(item.properties, 'nav')) {
        navFile = item;
        break;
      }
    }

    if (navFile?.file != null) {
      final targets = _tryReadEpub3Navigation(archive, navFile!.file!);
      if (targets.isNotEmpty) return targets;
    }

    _ManifestItem? ncxFile;
    final tocId = spine.tableOfContentsId;
    if (tocId != null) ncxFile = manifestById[tocId];
    ncxFile ??= _firstWhere(
      manifest,
      (item) =>
          item.file != null &&
          item.mediaType.toLowerCase() == 'application/x-dtbncx+xml',
    );
    if (ncxFile?.file == null) return const [];

    return _tryReadNcxNavigation(archive, ncxFile!.file!);
  }

  List<_NavigationTarget> _tryReadNcxNavigation(
    Archive archive,
    ArchiveFile navigationFile,
  ) {
    try {
      final document = _parseXml(navigationFile, 'EPUB NCX');
      final navMap = _firstDescendant(document, 'navMap');
      if (navMap == null) return const [];

      final result = <_NavigationTarget>[];
      void visit(XmlElement parent) {
        for (final point in _children(parent, 'navPoint')) {
          final content = _firstOrNull(_children(point, 'content'));
          final href = content == null ? null : _attribute(content, 'src');
          if (href != null && href.isNotEmpty) {
            final path = _resolveArchivePath(
              archive,
              _zipDirectory(navigationFile.name),
              href,
            );
            if (path != null) {
              final label = _firstDescendant(point, 'text')?.innerText.trim();
              result.add(_NavigationTarget(path: path, title: label));
            }
          }
          visit(point);
        }
      }

      visit(navMap);
      return result;
    } catch (_) {
      // 导航损坏不应阻断 spine/manifest 正文兜底。
      return const [];
    }
  }

  List<_NavigationTarget> _tryReadEpub3Navigation(
    Archive archive,
    ArchiveFile navigationFile,
  ) {
    try {
      final document = _parseXml(navigationFile, 'EPUB nav');
      final navElements = _descendants(document, 'nav').toList();
      XmlElement? tocNav;
      for (final nav in navElements) {
        if (_hasToken(_attribute(nav, 'type'), 'toc')) {
          tocNav = nav;
          break;
        }
      }
      tocNav ??= _firstWhere(
        navElements,
        (nav) => _children(nav, 'ol').isNotEmpty,
      );
      if (tocNav == null) return const [];

      final rootList = _firstOrNull(_children(tocNav, 'ol'));
      if (rootList == null) return const [];

      final result = <_NavigationTarget>[];
      void visit(XmlElement list) {
        for (final listItem in _children(list, 'li')) {
          final labelElement =
              _firstOrNull(_children(listItem, 'a')) ??
              _firstOrNull(_children(listItem, 'span'));
          if (labelElement != null) {
            final href = _attribute(labelElement, 'href');
            if (href != null && href.isNotEmpty) {
              final path = _resolveArchivePath(
                archive,
                _zipDirectory(navigationFile.name),
                href,
              );
              if (path != null) {
                result.add(
                  _NavigationTarget(
                    path: path,
                    title: labelElement.innerText.trim(),
                  ),
                );
              }
            }
          }
          final nestedList = _firstOrNull(_children(listItem, 'ol'));
          if (nestedList != null) visit(nestedList);
        }
      }

      visit(rootList);
      return result;
    } catch (_) {
      // 导航损坏不应阻断 spine/manifest 正文兜底。
      return const [];
    }
  }

  String _readPackagePath(Archive archive) {
    final containerFile = _findArchiveFile(archive, 'META-INF/container.xml');
    if (containerFile == null) {
      throw const FormatException('EPUB 缺少 META-INF/container.xml');
    }

    final document = _parseXml(containerFile, 'EPUB container');
    final rootFiles = _descendants(document, 'rootfile');
    for (final rootFile in rootFiles) {
      final path = _attribute(rootFile, 'full-path');
      if (path == null || path.isEmpty) continue;
      final mediaType = _attribute(rootFile, 'media-type');
      if (mediaType == null ||
          mediaType.toLowerCase() == 'application/oebps-package+xml') {
        final resolved = _resolveArchivePath(archive, '', path);
        if (resolved != null) return resolved;
      }
    }
    throw const FormatException('EPUB container 未找到有效根文件');
  }

  ArchiveFile? _resolveArchiveFile(
    Archive archive,
    String baseDirectory,
    String href,
  ) {
    final path = _resolveArchivePath(archive, baseDirectory, href);
    return path == null ? null : _findArchiveFile(archive, path);
  }

  String? _resolveArchivePath(
    Archive archive,
    String baseDirectory,
    String href,
  ) {
    final rawPath = _hrefPath(href);
    if (rawPath.isEmpty) return null;

    final candidates = <String>{};
    void addCandidate(String value) {
      final normalized = _normalizeZipPath(value);
      if (normalized.isNotEmpty) candidates.add(normalized);
    }

    addCandidate(p.posix.join(baseDirectory, rawPath));
    try {
      addCandidate(p.posix.join(baseDirectory, Uri.decodeFull(rawPath)));
    } catch (_) {}

    for (final candidate in candidates) {
      final file = _findArchiveFile(archive, candidate);
      if (file != null) return file.name;
    }
    return null;
  }

  ArchiveFile? _findArchiveFile(Archive archive, String path) {
    final normalized = _normalizeZipPath(path);
    ArchiveFile? caseInsensitiveMatch;
    for (final file in archive.files) {
      final filePath = _normalizeZipPath(file.name);
      if (filePath == normalized) return file;
      if (filePath.toLowerCase() == normalized.toLowerCase()) {
        caseInsensitiveMatch ??= file;
      }
    }
    return caseInsensitiveMatch;
  }

  _ManifestItem? _findManifestByPath(
    List<_ManifestItem> manifest,
    String path,
  ) {
    for (final item in manifest) {
      if (item.file?.name == path) return item;
    }
    return null;
  }

  bool _isTextItem(_ManifestItem item) {
    if (_hasToken(item.properties, 'nav')) return false;
    return _textMediaTypes.contains(item.mediaType.toLowerCase().trim());
  }

  XmlDocument _parseXml(ArchiveFile file, String description) {
    try {
      return XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
    } catch (error) {
      throw FormatException('$description 解析失败：$error');
    }
  }

  static Iterable<XmlElement> _children(XmlElement parent, String name) {
    return parent.children.whereType<XmlElement>().where(
      (element) => element.name.local.toLowerCase() == name.toLowerCase(),
    );
  }

  static Iterable<XmlElement> _descendants(XmlNode parent, String name) {
    return parent.descendants.whereType<XmlElement>().where(
      (element) => element.name.local.toLowerCase() == name.toLowerCase(),
    );
  }

  static XmlElement? _firstDescendant(XmlNode parent, String name) {
    return _firstOrNull(_descendants(parent, name));
  }

  static T? _firstOrNull<T>(Iterable<T> values) {
    for (final value in values) {
      return value;
    }
    return null;
  }

  static T? _firstWhere<T>(Iterable<T> values, bool Function(T value) test) {
    for (final value in values) {
      if (test(value)) return value;
    }
    return null;
  }

  static String? _attribute(XmlElement element, String name) {
    for (final attribute in element.attributes) {
      if (attribute.name.local.toLowerCase() == name.toLowerCase()) {
        return attribute.value;
      }
    }
    return null;
  }

  static bool _hasToken(String? value, String token) {
    if (value == null || value.trim().isEmpty) return false;
    return value
        .split(RegExp(r'\s+'))
        .any((item) => item.toLowerCase() == token.toLowerCase());
  }

  static String _hrefPath(String href) {
    final withoutFragment = href.split('#').first;
    final withoutQuery = withoutFragment.split('?').first;
    try {
      return Uri.decodeFull(withoutQuery);
    } catch (_) {
      return withoutQuery;
    }
  }

  static String _normalizeZipPath(String value) {
    var path = value.replaceAll('\\', '/');
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    path = p.posix.normalize(path);
    return path == '.' ? '' : path;
  }

  static String _zipDirectory(String path) {
    final directory = p.posix.dirname(_normalizeZipPath(path));
    return directory == '.' ? '' : directory;
  }
}

class _ManifestItem {
  final String id;
  final String mediaType;
  final String? properties;
  final ArchiveFile? file;

  const _ManifestItem({
    required this.id,
    required this.mediaType,
    required this.properties,
    required this.file,
  });
}

class _SpineData {
  final List<String> idRefs;
  final String? tableOfContentsId;

  const _SpineData({this.idRefs = const [], this.tableOfContentsId});
}

class _NavigationTarget {
  final String path;
  final String? title;

  const _NavigationTarget({required this.path, required this.title});
}
