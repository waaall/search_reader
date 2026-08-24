// 阅读器状态管理：逻辑章节保持稳定，正文只按内部渲染分片读取。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../core/db/render_segment_service.dart';
import '../../core/storage/book_storage.dart';
import '../../domain/book.dart';
import '../../domain/chapter.dart';
import '../../domain/reading_progress.dart';
import '../../domain/render_segment.dart';

class ReaderState {
  final Book book;
  final List<Chapter> chapters;
  final int currentChapterIndex;
  final List<RenderSegment> currentChapterSegments;
  final int initialSegmentIndex;
  final String initialSegmentText;
  final int initialCharOffset;
  final int jumpToken;

  const ReaderState({
    required this.book,
    required this.chapters,
    required this.currentChapterIndex,
    required this.currentChapterSegments,
    required this.initialSegmentIndex,
    required this.initialSegmentText,
    required this.initialCharOffset,
    this.jumpToken = 0,
  });

  Chapter get currentChapter => chapters[currentChapterIndex];
  bool get hasPrev => currentChapterIndex > 0;
  bool get hasNext => currentChapterIndex < chapters.length - 1;

  ReaderState copyWith({
    int? currentChapterIndex,
    List<RenderSegment>? currentChapterSegments,
    int? initialSegmentIndex,
    String? initialSegmentText,
    int? initialCharOffset,
    int? jumpToken,
  }) {
    return ReaderState(
      book: book,
      chapters: chapters,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      currentChapterSegments:
          currentChapterSegments ?? this.currentChapterSegments,
      initialSegmentIndex: initialSegmentIndex ?? this.initialSegmentIndex,
      initialSegmentText: initialSegmentText ?? this.initialSegmentText,
      initialCharOffset: initialCharOffset ?? this.initialCharOffset,
      jumpToken: jumpToken ?? this.jumpToken,
    );
  }
}

class ReaderNotifier extends AutoDisposeFamilyAsyncNotifier<ReaderState, int> {
  final BookDao _bookDao = BookDao();
  final ChapterDao _chapterDao = ChapterDao();
  final ProgressDao _progressDao = ProgressDao();
  final RenderSegmentService _segmentService = RenderSegmentService();

  Future<void> _progressSaveQueue = Future.value();
  int _navigationToken = 0;

  @override
  Future<ReaderState> build(int bookId) async {
    final book = await _bookDao.findById(bookId);
    if (book == null) throw StateError('Book not found: id=$bookId');
    final chapters = await _chapterDao.listByBook(bookId);
    if (chapters.isEmpty) {
      throw StateError('Book has no chapter data: id=$bookId');
    }
    final progress = await _progressDao.get(bookId);
    final initialIndex = (progress?.chapterIndex ?? 0).clamp(
      0,
      chapters.length - 1,
    );
    final chapter = chapters[initialIndex];
    final offset = (progress?.charOffset ?? 0).clamp(0, chapter.charCount);
    final loaded = await _loadChapter(book, chapter, offset);

    await _bookDao.updateLastRead(bookId);
    return ReaderState(
      book: book,
      chapters: chapters,
      currentChapterIndex: initialIndex,
      currentChapterSegments: loaded.segments,
      initialSegmentIndex: loaded.segmentIndex,
      initialSegmentText: loaded.text,
      initialCharOffset: offset,
    );
  }

  Future<void> jumpToChapter(int chapterIndex, {int charOffset = 0}) async {
    final cur = state.value;
    if (cur == null) return;
    final requestToken = ++_navigationToken;
    final clampedIndex = chapterIndex.clamp(0, cur.chapters.length - 1);
    final chapter = cur.chapters[clampedIndex];
    final clampedOffset = charOffset.clamp(0, chapter.charCount);
    final loaded = await _loadChapter(cur.book, chapter, clampedOffset);
    if (requestToken != _navigationToken || state.value == null) return;

    state = AsyncData(
      cur.copyWith(
        currentChapterIndex: clampedIndex,
        currentChapterSegments: loaded.segments,
        initialSegmentIndex: loaded.segmentIndex,
        initialSegmentText: loaded.text,
        initialCharOffset: clampedOffset,
        jumpToken: cur.jumpToken + 1,
      ),
    );
    await _saveProgressFor(cur.book.id, clampedIndex, clampedOffset);
  }

  Future<void> nextChapter() async {
    final cur = state.value;
    if (cur != null && cur.hasNext) {
      await jumpToChapter(cur.currentChapterIndex + 1);
    }
  }

  Future<void> prevChapter() async {
    final cur = state.value;
    if (cur != null && cur.hasPrev) {
      await jumpToChapter(cur.currentChapterIndex - 1);
    }
  }

  // 视图按索引读取单个分片；返回前校验字符长度，尽早暴露范围损坏。
  Future<String> readSegmentText(int segmentIndex) async {
    final cur = state.value;
    if (cur == null) throw StateError('阅读器尚未加载完成');
    if (segmentIndex < 0 || segmentIndex >= cur.currentChapterSegments.length) {
      throw RangeError.index(
        segmentIndex,
        cur.currentChapterSegments,
        'segmentIndex',
      );
    }
    return _readSegment(cur.book, cur.currentChapterSegments[segmentIndex]);
  }

  Future<void> saveProgress(int charOffsetInChapter) async {
    final cur = state.value;
    if (cur == null) return;
    final clampedOffset = charOffsetInChapter.clamp(
      0,
      cur.currentChapter.charCount,
    );
    if (cur.initialCharOffset != clampedOffset) {
      state = AsyncData(cur.copyWith(initialCharOffset: clampedOffset));
    }
    await _saveProgressFor(cur.book.id, cur.currentChapterIndex, clampedOffset);
  }

  Future<_LoadedChapter> _loadChapter(
    Book book,
    Chapter chapter,
    int charOffset,
  ) async {
    final segments = await _segmentService.ensureForChapter(book, chapter);
    final segmentIndex = _segmentIndexForOffset(segments, chapter, charOffset);
    final text = await _readSegment(book, segments[segmentIndex]);
    return _LoadedChapter(
      segments: segments,
      segmentIndex: segmentIndex,
      text: text,
    );
  }

  int _segmentIndexForOffset(
    List<RenderSegment> segments,
    Chapter chapter,
    int chapterOffset,
  ) {
    final globalOffset = chapter.startChar + chapterOffset;
    for (var index = 0; index < segments.length; index++) {
      if (globalOffset < segments[index].endChar ||
          index == segments.length - 1) {
        return index;
      }
    }
    return segments.length - 1;
  }

  Future<String> _readSegment(Book book, RenderSegment segment) async {
    final text = await BookStorage.shared.readTextRange(
      book.filePath,
      startByte: segment.startByte,
      endByte: segment.endByte,
    );
    if (text.length != segment.charCount) {
      throw StateError('渲染分片字符范围与 UTF-8 字节范围不一致');
    }
    return text;
  }

  Future<void> _saveProgressFor(
    int bookId,
    int chapterIndex,
    int charOffsetInChapter,
  ) {
    final progress = ReadingProgress(
      bookId: bookId,
      chapterIndex: chapterIndex,
      charOffset: charOffsetInChapter,
      updatedAt: DateTime.now(),
    );
    final save = _progressSaveQueue.then((_) => _progressDao.save(progress));
    _progressSaveQueue = save.catchError((_) {});
    return save;
  }
}

class _LoadedChapter {
  final List<RenderSegment> segments;
  final int segmentIndex;
  final String text;

  const _LoadedChapter({
    required this.segments,
    required this.segmentIndex,
    required this.text,
  });
}

final readerProvider = AsyncNotifierProvider.autoDispose
    .family<ReaderNotifier, ReaderState, int>(ReaderNotifier.new);
