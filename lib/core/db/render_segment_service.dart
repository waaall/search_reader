// 渲染分片服务：读取导入时生成的范围，并为旧书按章节流式补建缺失数据。
import 'dart:developer' as developer;

import '../../domain/book.dart';
import '../../domain/chapter.dart';
import '../../domain/render_segment.dart';
import '../parser/render_segmenter.dart';
import '../storage/book_storage.dart';
import 'daos.dart';

class RenderSegmentService {
  RenderSegmentService({
    RenderSegmentDao? dao,
    BookStorage? storage,
    StreamingRenderSegmentBuilder? builder,
  }) : _dao = dao ?? RenderSegmentDao(),
       _storage = storage ?? BookStorage.shared,
       _builder = builder ?? const StreamingRenderSegmentBuilder();

  final RenderSegmentDao _dao;
  final BookStorage _storage;
  final StreamingRenderSegmentBuilder _builder;
  final Map<int, Future<List<RenderSegment>>> _pendingBuilds = {};

  Future<List<RenderSegment>> ensureForChapter(Book book, Chapter chapter) {
    return _pendingBuilds.putIfAbsent(chapter.id, () async {
      try {
        try {
          final current = await _dao.listByChapter(chapter.id);
          if (_coversChapter(current, chapter)) return current;
        } catch (error, stackTrace) {
          _reportCacheFailure(chapter.id, error, stackTrace);
        }

        final descriptors = await _builder.build(
          chunks: _storage.readUtf8RangeChunks(
            book.filePath,
            startByte: chapter.startByte,
            endByte: chapter.endByte,
            chunkBytes: 16 * 1024,
          ),
          startChar: chapter.startChar,
          endChar: chapter.endChar,
          startByte: chapter.startByte,
          endByte: chapter.endByte,
        );
        final inMemory = [
          for (var index = 0; index < descriptors.length; index++)
            RenderSegment(
              // 负数表示尚未持久化的分片；阅读定位只依赖章节、索引和范围。
              id: -index - 1,
              chapterId: chapter.id,
              segmentIndex: index,
              startChar: descriptors[index].startChar,
              endChar: descriptors[index].endChar,
              startByte: descriptors[index].startByte,
              endByte: descriptors[index].endByte,
            ),
        ];
        // 正文与范围错误仍然失败，只有派生缓存的读写错误允许降级。
        if (!_coversChapter(inMemory, chapter)) {
          throw StateError('渲染分片补建后仍未完整覆盖章节：${chapter.id}');
        }
        try {
          await _dao.replaceChapterSegments(chapter.id, descriptors);
          final rebuilt = await _dao.listByChapter(chapter.id);
          if (_coversChapter(rebuilt, chapter)) return rebuilt;
          throw StateError('持久化分片未完整覆盖章节：${chapter.id}');
        } catch (error, stackTrace) {
          _reportCacheFailure(chapter.id, error, stackTrace);
          return inMemory;
        }
      } finally {
        _pendingBuilds.remove(chapter.id);
      }
    });
  }

  void _reportCacheFailure(int chapterId, Object error, StackTrace stackTrace) {
    developer.log(
      '分片缓存暂时不可用，使用正文生成的有效范围继续阅读：$chapterId',
      name: 'search_reader.render_segments',
      error: error,
      stackTrace: stackTrace,
    );
  }

  bool _coversChapter(List<RenderSegment> segments, Chapter chapter) {
    if (segments.isEmpty) return false;
    var nextChar = chapter.startChar;
    var nextByte = chapter.startByte;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (segment.chapterId != chapter.id ||
          segment.segmentIndex != index ||
          segment.startChar != nextChar ||
          segment.startByte != nextByte ||
          segment.endChar < segment.startChar ||
          segment.endByte < segment.startByte ||
          segment.charCount > _builder.segmenter.policy.maxChars ||
          (segment.charCount == 0 && chapter.charCount != 0)) {
        return false;
      }
      nextChar = segment.endChar;
      nextByte = segment.endByte;
    }
    return nextChar == chapter.endChar && nextByte == chapter.endByte;
  }
}
