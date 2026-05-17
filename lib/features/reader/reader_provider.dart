import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos.dart';
import '../../core/encoding/text_decoder.dart';
import '../../core/storage/book_storage.dart';
import '../../domain/book.dart';
import '../../domain/chapter.dart';
import '../../domain/reading_progress.dart';

// 阅读器状态：当前书 + 章节列表 + 当前章节正文 + 初始字符偏移
class ReaderState {
  final Book book;
  final List<Chapter> chapters;
  final int currentChapterIndex;
  final String currentChapterText;
  final int initialCharOffset; // 第一次进入页面时的章节内偏移
  final int jumpToken; // 跳转计数：每次跳章/跳书签自增，用于强制阅读视图重建

  const ReaderState({
    required this.book,
    required this.chapters,
    required this.currentChapterIndex,
    required this.currentChapterText,
    required this.initialCharOffset,
    this.jumpToken = 0,
  });

  Chapter get currentChapter => chapters[currentChapterIndex];
  bool get hasPrev => currentChapterIndex > 0;
  bool get hasNext => currentChapterIndex < chapters.length - 1;

  ReaderState copyWith({
    int? currentChapterIndex,
    String? currentChapterText,
    int? initialCharOffset,
    int? jumpToken,
  }) {
    return ReaderState(
      book: book,
      chapters: chapters,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      currentChapterText: currentChapterText ?? this.currentChapterText,
      initialCharOffset: initialCharOffset ?? this.initialCharOffset,
      jumpToken: jumpToken ?? this.jumpToken,
    );
  }
}

class ReaderNotifier extends AutoDisposeFamilyAsyncNotifier<ReaderState, int> {
  final BookDao _bookDao = BookDao();
  final ChapterDao _chapterDao = ChapterDao();
  final ProgressDao _progressDao = ProgressDao();

  // 全文缓存：避免每次切章重新读盘解码
  String? _fullText;

  @override
  Future<ReaderState> build(int bookId) async {
    final book = await _bookDao.findById(bookId);
    if (book == null) {
      throw StateError('Book not found: id=$bookId');
    }
    final chapters = await _chapterDao.listByBook(bookId);
    if (chapters.isEmpty) {
      throw StateError('Book has no chapter data: id=$bookId');
    }
    final progress = await _progressDao.get(bookId);
    final initialIndex = (progress?.chapterIndex ?? 0)
        .clamp(0, chapters.length - 1);

    await _ensureFullText(book);
    final text = _sliceChapter(chapters[initialIndex]);

    // 更新最近阅读时间（不阻塞返回）
    await _bookDao.updateLastRead(bookId);

    return ReaderState(
      book: book,
      chapters: chapters,
      currentChapterIndex: initialIndex,
      currentChapterText: text,
      initialCharOffset: progress?.charOffset ?? 0,
    );
  }

  // 跳转到指定章节
  Future<void> jumpToChapter(int chapterIndex, {int charOffset = 0}) async {
    final cur = state.value;
    if (cur == null) return;
    final clamped = chapterIndex.clamp(0, cur.chapters.length - 1);
    await _ensureFullText(cur.book);
    final text = _sliceChapter(cur.chapters[clamped]);
    state = AsyncData(cur.copyWith(
      currentChapterIndex: clamped,
      currentChapterText: text,
      initialCharOffset: charOffset,
      jumpToken: cur.jumpToken + 1, // 自增以强制阅读视图按新位置重建
    ));
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

  // 保存当前阅读进度（widget 在翻页时调用）
  Future<void> saveProgress(int charOffsetInChapter) async {
    final cur = state.value;
    if (cur == null) return;
    await _progressDao.save(ReadingProgress(
      bookId: cur.book.id,
      chapterIndex: cur.currentChapterIndex,
      charOffset: charOffsetInChapter,
      updatedAt: DateTime.now(),
    ));
  }

  // 读全文（带缓存）
  Future<void> _ensureFullText(Book book) async {
    if (_fullText != null) return;
    final abs = await BookStorage.resolveAbsolute(book.filePath);
    final bytes = await File(abs).readAsBytes();
    final decoded = TextDecoder.decode(Uint8List.fromList(bytes));
    _fullText =
        decoded.content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  // 按章节起止位置截取文本
  String _sliceChapter(Chapter chapter) {
    final full = _fullText!;
    final start = chapter.startChar.clamp(0, full.length);
    final end = chapter.endChar.clamp(0, full.length);
    return full.substring(start, end);
  }
}

// autoDispose：退出阅读页后销毁 provider，
// 重新进入时 build() 会重新从数据库读取阅读进度，确保定位到上次位置
final readerProvider =
    AsyncNotifierProvider.autoDispose.family<ReaderNotifier, ReaderState, int>(
  ReaderNotifier.new,
);
