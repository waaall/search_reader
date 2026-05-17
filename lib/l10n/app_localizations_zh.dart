// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '小说阅读器';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDelete => '删除';

  @override
  String get commonSave => '保存';

  @override
  String get commonRetry => '重试';

  @override
  String get commonRetrying => '重试中…';

  @override
  String get commonSettings => '设置';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonDetails => '详情';

  @override
  String loadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get appStartupFailed => '应用启动失败';

  @override
  String get databaseInitializationFailed => '数据库初始化失败，暂时无法进入应用。';

  @override
  String get settingsTitle => '设置';

  @override
  String get systemSettingsSection => '系统设置';

  @override
  String get displayLanguage => '显示语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get readingSettingsSection => '阅读设置';

  @override
  String get fontSizeSection => '字号';

  @override
  String get fontSizeSmall => '小';

  @override
  String get fontSizeMedium => '中';

  @override
  String get fontSizeLarge => '大';

  @override
  String get fontSizeExtraLarge => '特大';

  @override
  String get lineHeightSection => '行距';

  @override
  String get lineHeightCompact => '紧凑';

  @override
  String get lineHeightNormal => '标准';

  @override
  String get lineHeightRelaxed => '宽松';

  @override
  String get readerThemeSection => '主题';

  @override
  String get readerThemeLight => '日间';

  @override
  String get readerThemeDark => '夜间';

  @override
  String get readerThemeSepia => '护眼';

  @override
  String get readingModeSection => '阅读模式';

  @override
  String get readingModePaginated => '翻页';

  @override
  String get readingModeScroll => '滚动';

  @override
  String get settingsPreviewText =>
      '夜色如水，月光在屋檐上铺成薄薄一层霜。她合上书本，听到风穿过竹林的声音，像极了多年前在江南听过的那一阵。';

  @override
  String get libraryTitle => '书架';

  @override
  String loadLibraryFailed(Object error) {
    return '加载书架失败：$error';
  }

  @override
  String get importBooks => '导入书籍';

  @override
  String get exitSelection => '退出多选';

  @override
  String selectedBooks(int count) {
    return '已选 $count 本';
  }

  @override
  String get selectAll => '全选';

  @override
  String get batchDelete => '批量删除';

  @override
  String confirmBatchDelete(int count) {
    return '确定删除选中的 $count 本书及其阅读进度？';
  }

  @override
  String get emptyLibraryHint => '书架为空，点击下方按钮导入 txt 或 epub 文件';

  @override
  String get unread => '未读';

  @override
  String lastReadAt(String time) {
    return '上次阅读 $time';
  }

  @override
  String get deleteBook => '删除书籍';

  @override
  String confirmDeleteBook(String title) {
    return '确定删除《$title》及其阅读进度？';
  }

  @override
  String fileTooLarge(String fileName) {
    return '$fileName 超过大小上限。';
  }

  @override
  String unsupportedFileFormats(String files) {
    return '以下文件格式不支持（仅 txt / epub）：\n$files';
  }

  @override
  String partialDeleteFailed(String details) {
    return '部分删除失败：\n$details';
  }

  @override
  String importFailed(String details) {
    return '导入失败：$details';
  }

  @override
  String importUnsupportedFormat(String extension) {
    return '不支持的文件格式：$extension';
  }

  @override
  String get importCannotDecode => '无法识别文件编码。';

  @override
  String get importUnexpectedFailure => '导入失败。';

  @override
  String importDetailPrefix(String details) {
    return '详情：$details';
  }

  @override
  String get importPhaseCopying => '正在复制文件';

  @override
  String get importPhaseParsing => '正在解析章节';

  @override
  String get importPhaseIndexing => '正在建立索引';

  @override
  String get importPhaseDone => '导入完成';

  @override
  String get searchHint => '搜索全部书籍内容';

  @override
  String searchFailed(Object error) {
    return '搜索失败：$error';
  }

  @override
  String get searchEmptyHint => '输入关键词，跨书检索章节内容';

  @override
  String get noSearchResults => '没有匹配结果';

  @override
  String get bookmarksTitle => '书签';

  @override
  String loadBookmarksFailed(Object error) {
    return '加载书签失败：$error';
  }

  @override
  String get deleteBookmark => '删除书签';

  @override
  String get confirmDeleteBookmark => '确定删除这条书签？';

  @override
  String get emptyBookmarksHint => '还没有书签\n阅读时点底部「书签」按钮可添加';

  @override
  String get bookmarkAdded => '书签已添加';

  @override
  String get addBookmark => '添加书签';

  @override
  String get bookmarkNoteHint => '备注（可留空）';

  @override
  String get contentsTitle => '目录';

  @override
  String get contentsAndBookmarks => '目录和书签';

  @override
  String get unknownChapter => '未知章节';

  @override
  String openBookFailed(Object error) {
    return '打开失败：$error';
  }

  @override
  String settingsLoadFailed(Object error) {
    return '设置加载失败：$error';
  }

  @override
  String get previousChapter => '上一章';

  @override
  String get nextChapter => '下一章';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String hoursAgo(int hours) {
    return '$hours 小时前';
  }

  @override
  String daysAgo(int days) {
    return '$days 天前';
  }

  @override
  String characterCount(int count) {
    return '$count 字';
  }

  @override
  String characterCountTenThousand(String value) {
    return '$value 万字';
  }
}
