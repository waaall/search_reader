// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Search Reader';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRetrying => 'Retrying…';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonDetails => 'Details';

  @override
  String loadFailed(Object error) {
    return 'Failed to load: $error';
  }

  @override
  String get appStartupFailed => 'App failed to start';

  @override
  String get databaseInitializationFailed =>
      'Database initialization failed, so the app cannot be opened right now.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get systemSettingsSection => 'System settings';

  @override
  String get displayLanguage => 'Display language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get languageSimplifiedChinese => 'Simplified Chinese';

  @override
  String get languageEnglish => 'English';

  @override
  String get readingSettingsSection => 'Reading settings';

  @override
  String get fontSizeSection => 'Font size';

  @override
  String get fontSizeSmall => 'Small';

  @override
  String get fontSizeMedium => 'Medium';

  @override
  String get fontSizeLarge => 'Large';

  @override
  String get fontSizeExtraLarge => 'Extra large';

  @override
  String get lineHeightSection => 'Line spacing';

  @override
  String get lineHeightCompact => 'Compact';

  @override
  String get lineHeightNormal => 'Standard';

  @override
  String get lineHeightRelaxed => 'Relaxed';

  @override
  String get readerThemeSection => 'Theme';

  @override
  String get readerThemeLight => 'Light';

  @override
  String get readerThemeDark => 'Dark';

  @override
  String get readerThemeSepia => 'Sepia';

  @override
  String get readingModeSection => 'Reading mode';

  @override
  String get readingModePaginated => 'Page';

  @override
  String get readingModeScroll => 'Scroll';

  @override
  String get settingsPreviewText =>
      'Moonlight lay like a thin frost over the eaves. She closed the book and listened to the wind moving through the bamboo, a sound that carried her back to Jiangnan years ago.';

  @override
  String get libraryTitle => 'Library';

  @override
  String loadLibraryFailed(Object error) {
    return 'Failed to load library: $error';
  }

  @override
  String get importBooks => 'Import books';

  @override
  String get exitSelection => 'Exit selection';

  @override
  String selectedBooks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books selected',
      one: '1 book selected',
      zero: 'No books selected',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Select all';

  @override
  String get batchDelete => 'Batch delete';

  @override
  String confirmBatchDelete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete the selected $count books and their reading progress?',
      one: 'Delete the selected book and its reading progress?',
    );
    return '$_temp0';
  }

  @override
  String get emptyLibraryHint =>
      'Your library is empty. Tap the button below to import txt or epub files.';

  @override
  String get unread => 'Unread';

  @override
  String lastReadAt(String time) {
    return 'Last read $time';
  }

  @override
  String get deleteBook => 'Delete book';

  @override
  String confirmDeleteBook(String title) {
    return 'Delete \"$title\" and its reading progress?';
  }

  @override
  String fileTooLarge(String fileName) {
    return '$fileName exceeds the size limit.';
  }

  @override
  String unsupportedFileFormats(String files) {
    return 'Unsupported file format. Only txt and epub are supported:\n$files';
  }

  @override
  String partialDeleteFailed(String details) {
    return 'Some books could not be deleted:\n$details';
  }

  @override
  String importFailed(String details) {
    return 'Import failed: $details';
  }

  @override
  String importUnsupportedFormat(String extension) {
    return 'Unsupported file format: $extension';
  }

  @override
  String get importCannotDecode => 'Unable to detect the text encoding.';

  @override
  String get importUnexpectedFailure => 'Import failed unexpectedly.';

  @override
  String importDetailPrefix(String details) {
    return 'Details: $details';
  }

  @override
  String get importPhaseCopying => 'Copying file';

  @override
  String get importPhaseParsing => 'Parsing chapters';

  @override
  String get importPhaseIndexing => 'Building index';

  @override
  String get importPhaseDone => 'Import complete';

  @override
  String get searchHint => 'Search all book content';

  @override
  String searchFailed(Object error) {
    return 'Search failed: $error';
  }

  @override
  String get searchEmptyHint =>
      'Enter keywords to search chapters across your library.';

  @override
  String get noSearchResults => 'No matching results';

  @override
  String get bookmarksTitle => 'Bookmarks';

  @override
  String loadBookmarksFailed(Object error) {
    return 'Failed to load bookmarks: $error';
  }

  @override
  String get deleteBookmark => 'Delete bookmark';

  @override
  String get confirmDeleteBookmark => 'Delete this bookmark?';

  @override
  String get emptyBookmarksHint =>
      'No bookmarks yet\nTap the bottom Bookmark button while reading to add one.';

  @override
  String get bookmarkAdded => 'Bookmark added';

  @override
  String get addBookmark => 'Add bookmark';

  @override
  String get bookmarkNoteHint => 'Note (optional)';

  @override
  String get contentsTitle => 'Contents';

  @override
  String get contentsAndBookmarks => 'Contents & bookmarks';

  @override
  String get unknownChapter => 'Unknown chapter';

  @override
  String openBookFailed(Object error) {
    return 'Failed to open: $error';
  }

  @override
  String settingsLoadFailed(Object error) {
    return 'Failed to load settings: $error';
  }

  @override
  String get previousChapter => 'Previous';

  @override
  String get nextChapter => 'Next';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String hoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String daysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String characterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '1 character',
    );
    return '$_temp0';
  }

  @override
  String characterCountTenThousand(String value) {
    return '${value}0K characters';
  }
}
