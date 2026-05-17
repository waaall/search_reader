import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Reader'**
  String get appTitle;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonRetrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying…'**
  String get commonRetrying;

  /// No description provided for @commonSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get commonDetails;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String loadFailed(Object error);

  /// No description provided for @appStartupFailed.
  ///
  /// In en, this message translates to:
  /// **'App failed to start'**
  String get appStartupFailed;

  /// No description provided for @databaseInitializationFailed.
  ///
  /// In en, this message translates to:
  /// **'Database initialization failed, so the app cannot be opened right now.'**
  String get databaseInitializationFailed;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @systemSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'System settings'**
  String get systemSettingsSection;

  /// No description provided for @displayLanguage.
  ///
  /// In en, this message translates to:
  /// **'Display language'**
  String get displayLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageSystem;

  /// No description provided for @languageSimplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get languageSimplifiedChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @readingSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'Reading settings'**
  String get readingSettingsSection;

  /// No description provided for @fontSizeSection.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSizeSection;

  /// No description provided for @fontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get fontSizeMedium;

  /// No description provided for @fontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontSizeLarge;

  /// No description provided for @fontSizeExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra large'**
  String get fontSizeExtraLarge;

  /// No description provided for @lineHeightSection.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get lineHeightSection;

  /// No description provided for @lineHeightCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get lineHeightCompact;

  /// No description provided for @lineHeightNormal.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get lineHeightNormal;

  /// No description provided for @lineHeightRelaxed.
  ///
  /// In en, this message translates to:
  /// **'Relaxed'**
  String get lineHeightRelaxed;

  /// No description provided for @readerThemeSection.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get readerThemeSection;

  /// No description provided for @readerThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get readerThemeLight;

  /// No description provided for @readerThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get readerThemeDark;

  /// No description provided for @readerThemeSepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get readerThemeSepia;

  /// No description provided for @readingModeSection.
  ///
  /// In en, this message translates to:
  /// **'Reading mode'**
  String get readingModeSection;

  /// No description provided for @readingModePaginated.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get readingModePaginated;

  /// No description provided for @readingModeScroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get readingModeScroll;

  /// No description provided for @settingsPreviewText.
  ///
  /// In en, this message translates to:
  /// **'Moonlight lay like a thin frost over the eaves. She closed the book and listened to the wind moving through the bamboo, a sound that carried her back to Jiangnan years ago.'**
  String get settingsPreviewText;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @loadLibraryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load library: {error}'**
  String loadLibraryFailed(Object error);

  /// No description provided for @importBooks.
  ///
  /// In en, this message translates to:
  /// **'Import books'**
  String get importBooks;

  /// No description provided for @exitSelection.
  ///
  /// In en, this message translates to:
  /// **'Exit selection'**
  String get exitSelection;

  /// No description provided for @selectedBooks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No books selected} =1{1 book selected} other{{count} books selected}}'**
  String selectedBooks(int count);

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @batchDelete.
  ///
  /// In en, this message translates to:
  /// **'Batch delete'**
  String get batchDelete;

  /// No description provided for @confirmBatchDelete.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete the selected book and its reading progress?} other{Delete the selected {count} books and their reading progress?}}'**
  String confirmBatchDelete(int count);

  /// No description provided for @emptyLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty. Tap the button below to import txt or epub files.'**
  String get emptyLibraryHint;

  /// No description provided for @unread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unread;

  /// No description provided for @lastReadAt.
  ///
  /// In en, this message translates to:
  /// **'Last read {time}'**
  String lastReadAt(String time);

  /// No description provided for @deleteBook.
  ///
  /// In en, this message translates to:
  /// **'Delete book'**
  String get deleteBook;

  /// No description provided for @confirmDeleteBook.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" and its reading progress?'**
  String confirmDeleteBook(String title);

  /// No description provided for @fileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'{fileName} exceeds the size limit.'**
  String fileTooLarge(String fileName);

  /// No description provided for @unsupportedFileFormats.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file format. Only txt and epub are supported:\n{files}'**
  String unsupportedFileFormats(String files);

  /// No description provided for @partialDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Some books could not be deleted:\n{details}'**
  String partialDeleteFailed(String details);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {details}'**
  String importFailed(String details);

  /// No description provided for @importUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file format: {extension}'**
  String importUnsupportedFormat(String extension);

  /// No description provided for @importCannotDecode.
  ///
  /// In en, this message translates to:
  /// **'Unable to detect the text encoding.'**
  String get importCannotDecode;

  /// No description provided for @importUnexpectedFailure.
  ///
  /// In en, this message translates to:
  /// **'Import failed unexpectedly.'**
  String get importUnexpectedFailure;

  /// No description provided for @importDetailPrefix.
  ///
  /// In en, this message translates to:
  /// **'Details: {details}'**
  String importDetailPrefix(String details);

  /// No description provided for @importPhaseCopying.
  ///
  /// In en, this message translates to:
  /// **'Copying file'**
  String get importPhaseCopying;

  /// No description provided for @importPhaseParsing.
  ///
  /// In en, this message translates to:
  /// **'Parsing chapters'**
  String get importPhaseParsing;

  /// No description provided for @importPhaseIndexing.
  ///
  /// In en, this message translates to:
  /// **'Building index'**
  String get importPhaseIndexing;

  /// No description provided for @importPhaseDone.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get importPhaseDone;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search all book content'**
  String get searchHint;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String searchFailed(Object error);

  /// No description provided for @searchEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter keywords to search chapters across your library.'**
  String get searchEmptyHint;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No matching results'**
  String get noSearchResults;

  /// No description provided for @bookmarksTitle.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarksTitle;

  /// No description provided for @loadBookmarksFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load bookmarks: {error}'**
  String loadBookmarksFailed(Object error);

  /// No description provided for @deleteBookmark.
  ///
  /// In en, this message translates to:
  /// **'Delete bookmark'**
  String get deleteBookmark;

  /// No description provided for @confirmDeleteBookmark.
  ///
  /// In en, this message translates to:
  /// **'Delete this bookmark?'**
  String get confirmDeleteBookmark;

  /// No description provided for @emptyBookmarksHint.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet\nTap the bottom Bookmark button while reading to add one.'**
  String get emptyBookmarksHint;

  /// No description provided for @bookmarkAdded.
  ///
  /// In en, this message translates to:
  /// **'Bookmark added'**
  String get bookmarkAdded;

  /// No description provided for @addBookmark.
  ///
  /// In en, this message translates to:
  /// **'Add bookmark'**
  String get addBookmark;

  /// No description provided for @bookmarkNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get bookmarkNoteHint;

  /// No description provided for @contentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get contentsTitle;

  /// No description provided for @contentsAndBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Contents & bookmarks'**
  String get contentsAndBookmarks;

  /// No description provided for @unknownChapter.
  ///
  /// In en, this message translates to:
  /// **'Unknown chapter'**
  String get unknownChapter;

  /// No description provided for @openBookFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open: {error}'**
  String openBookFailed(Object error);

  /// No description provided for @settingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load settings: {error}'**
  String settingsLoadFailed(Object error);

  /// No description provided for @previousChapter.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previousChapter;

  /// No description provided for @nextChapter.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextChapter;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute ago} other{{minutes} minutes ago}}'**
  String minutesAgo(int minutes);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour ago} other{{hours} hours ago}}'**
  String hoursAgo(int hours);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day ago} other{{days} days ago}}'**
  String daysAgo(int days);

  /// No description provided for @characterCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 character} other{{count} characters}}'**
  String characterCount(int count);

  /// No description provided for @characterCountTenThousand.
  ///
  /// In en, this message translates to:
  /// **'{value}0K characters'**
  String characterCountTenThousand(String value);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
