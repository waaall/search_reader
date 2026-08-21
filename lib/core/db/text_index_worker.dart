// 索引 token worker：把 bigram 生成移出调用方 isolate，同时保持单个章节的内存上限。
import 'dart:async';
import 'dart:isolate';

import 'text_index.dart';

class ChapterIndexTokens {
  final String title;
  final String search;

  const ChapterIndexTokens({required this.title, required this.search});
}

class TextIndexWorker {
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _responsePort;
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;
  Completer<SendPort>? _readyCompleter;
  Future<void>? _startFuture;
  final _pending = <int, Completer<ChapterIndexTokens>>{};
  int _nextRequestId = 0;
  bool _closed = false;

  Future<ChapterIndexTokens> tokenize({
    required String title,
    required String content,
  }) async {
    if (_closed) throw StateError('索引 worker 已关闭');
    final workerPort = await _worker();

    final id = _nextRequestId++;
    final completer = Completer<ChapterIndexTokens>();
    _pending[id] = completer;
    try {
      workerPort.send({
        'id': id,
        'title': title,
        'content': content,
        'replyPort': _responsePort!.sendPort,
      });
    } catch (error, stackTrace) {
      _pending.remove(id);
      completer.completeError(error, stackTrace);
      _failPending(StateError('索引 worker 无法接收任务：$error'));
    }
    return completer.future;
  }

  // worker 意外退出后允许下一次调用重新拉起，避免请求永久等待。
  Future<SendPort> _worker() async {
    while (true) {
      if (_closed) throw StateError('索引 worker 已关闭');
      await _ensureStarted();
      final port = _workerPort;
      if (port != null) return port;
      // 生命周期监听可能刚刚清空了已退出的 worker，重新进入启动流程。
      _startFuture = null;
    }
  }

  Future<void> _ensureStarted() async {
    final existing = _startFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final future = _start();
    _startFuture = future;
    try {
      await future;
    } catch (_) {
      if (identical(_startFuture, future)) _startFuture = null;
      rethrow;
    }
  }

  Future<void> _start() async {
    final readyPort = ReceivePort();
    final responsePort = ReceivePort();
    final readyCompleter = Completer<SendPort>();
    StreamSubscription<Object?>? readySubscription;
    _responsePort = responsePort;
    responsePort.listen(_handleResponse);
    _readyCompleter = readyCompleter;
    readySubscription = readyPort.listen((message) {
      if (message is SendPort && !readyCompleter.isCompleted) {
        readyCompleter.complete(message);
      }
    });
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(_textIndexWorkerMain, readyPort.sendPort);
      _isolate = isolate;
      _listenToLifecycle(isolate);
      _workerPort = await readyCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('索引 worker 启动超时'),
      );
    } catch (_) {
      // 启动阶段没有拿到 SendPort 时也要终止孤立 worker，避免后续重试叠加后台任务。
      if (isolate != null && identical(_isolate, isolate)) {
        isolate.kill(priority: Isolate.immediate);
        _errorPort?.close();
        _exitPort?.close();
        _errorPort = null;
        _exitPort = null;
        _isolate = null;
        _workerPort = null;
        if (identical(_responsePort, responsePort)) {
          responsePort.close();
          _responsePort = null;
        }
      }
      rethrow;
    } finally {
      await readySubscription.cancel();
      readyPort.close();
      if (identical(_readyCompleter, readyCompleter)) {
        _readyCompleter = null;
      }
    }
  }

  void _listenToLifecycle(Isolate isolate) {
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    _errorPort = errorPort;
    _exitPort = exitPort;
    isolate.addErrorListener(errorPort.sendPort);
    isolate.addOnExitListener(exitPort.sendPort);
    errorPort.listen((message) {
      final detail = message is List && message.isNotEmpty
          ? message.first
          : message;
      _failPending(StateError('索引 worker 异常退出：$detail'));
    });
    exitPort.listen((_) {
      _failPending(StateError('索引 worker 意外退出'));
    });
  }

  void _failPending(Object error) {
    if (_closed) return;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    final isolate = _isolate;
    isolate?.kill(priority: Isolate.immediate);
    _workerPort = null;
    _isolate = null;
    _errorPort?.close();
    _exitPort?.close();
    _responsePort?.close();
    _errorPort = null;
    _exitPort = null;
    _responsePort = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    _startFuture = null;
  }

  void _handleResponse(Object? message) {
    if (message is! Map) return;
    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (message['error'] is String) {
      completer.completeError(StateError(message['error']));
      return;
    }
    completer.complete(
      ChapterIndexTokens(
        title: message['title'] as String,
        search: message['search'] as String,
      ),
    );
  }

  // 导入结束后立即释放 worker，避免每次导入都遗留 isolate。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _workerPort?.send({'type': 'close'});
    _isolate?.kill(priority: Isolate.immediate);
    _errorPort?.close();
    _exitPort?.close();
    _responsePort?.close();
    final ready = _readyCompleter;
    final error = StateError('索引 worker 已关闭');
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    _errorPort = null;
    _exitPort = null;
    _responsePort = null;
    _workerPort = null;
    _isolate = null;
  }
}

Future<void> _textIndexWorkerMain(SendPort parentPort) async {
  final requestPort = ReceivePort();
  parentPort.send(requestPort.sendPort);
  await for (final message in requestPort) {
    if (message is! Map) continue;
    if (message['type'] == 'close') break;

    final id = message['id'];
    final replyPort = message['replyPort'];
    if (id is! int || replyPort is! SendPort) continue;
    try {
      replyPort.send({
        'id': id,
        'title': toBigramTokens(message['title'] as String),
        'search': toBigramTokens(message['content'] as String),
      });
    } catch (error) {
      replyPort.send({'id': id, 'error': '$error'});
    }
  }
  requestPort.close();
}
