# search_reader

[简体中文](README_ZH.md) | English

A local fiction reader. The goal is to import txt / epub novels into the device sandbox and provide a library, reading progress, full-text search, bookmarks, and adjustable reading experience. All books and indexes are stored locally and do not rely on any cloud service.

## Current Features

- Import local txt / epub files and copy them into the app sandbox.
- Automatically detect common Chinese text encodings: UTF-8, UTF-16, GBK / GB18030.
- Parse novels by chapter; if no chapter can be detected, the whole book is treated as a single chapter.
- Sort the library by recent reading activity, with import progress and error prompts.
- Reader page supports two reading modes:
  - **Paginated mode**: paginates with `TextPainter` based on font size, line spacing, and screen size.
  - **Scroll mode**: continuous scrolling, with progress saved after scrolling stops.
- Reading settings: font size, line spacing, light / dark / sepia themes, and paginated / scroll modes.
- Persist reading progress and restore the last position when reopening a book.
- Bookmarks: add bookmarks from the reader, view them in the contents / bookmarks drawer, and view or delete them from the global bookmarks page.
- Full-text search: SQLite FTS5 + Dart-side bigram index, supporting Chinese keywords with 2 or more characters; search results can jump to the matching chapter position.
- App-level theme uses `flex_color_scheme` for consistent Material component radius and interaction effects.
- Library, search, bookmarks, and other pages use lightweight entrance animations; the text scrolling area avoids high-frequency rebuilds.

## Tech Stack

- Flutter 3.x / Dart 3.x
- Riverpod 2.x
- SQLite: `sqflite` + `sqflite_common_ffi`
- FTS5: `unicode61` + Dart bigram tokens
- Files and paths: `file_picker`, `path_provider`, `path`
- Text and book parsing: `enough_convert`, `epubx`, `html`, `archive`
- Themes and animations: `flex_color_scheme`, `flutter_animate`

## Documentation

The project documentation is currently written in Chinese:

- Product requirements: [`docs/demand/01-product-requirements.md`](docs/demand/01-product-requirements.md)
- Technical design: [`docs/dev/02-technical-design.md`](docs/dev/02-technical-design.md)
- Build and release: [`docs/dev/03-build-and-release.md`](docs/dev/03-build-and-release.md)

## Local Development

```bash
flutter pub get
flutter run
```

Common checks:

```bash
flutter analyze
flutter test
```

## Build

Detailed Android / macOS toolchain instructions are available in [`docs/dev/03-build-and-release.md`](docs/dev/03-build-and-release.md). After the environment is configured, common commands are:

```bash
flutter build apk      # Android APK
flutter build macos    # macOS .app
```

> The current Android release build still uses the debug signing key. This is suitable for personal use or small-scale distribution; replace it with a release keystore before publishing to an app store.

## Data & Privacy

- Book files are copied into the `books/` subdirectory under the app documents directory.
- The database file is `search_reader.db`; it stores book metadata, chapters, indexes, reading progress, settings, and bookmarks.
- Full-text indexes and reading data are stored only on the local device.
