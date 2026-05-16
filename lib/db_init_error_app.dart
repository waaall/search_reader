import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/db/database.dart';
import 'shared/theme/app_theme.dart';

// 数据库初始化失败时的兜底 App：避免卡在 runApp 之前导致黑屏。
// 展示真实错误信息并提供重试入口；重试成功后用正常 App 替换根 widget。
class DbInitErrorApp extends StatelessWidget {
  const DbInitErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小说阅读器',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: _DbInitErrorPage(error: error),
    );
  }
}

class _DbInitErrorPage extends StatefulWidget {
  const _DbInitErrorPage({required this.error});

  final Object error;

  @override
  State<_DbInitErrorPage> createState() => _DbInitErrorPageState();
}

class _DbInitErrorPageState extends State<_DbInitErrorPage> {
  late Object _error = widget.error;
  bool _retrying = false;

  // 重试数据库初始化：成功则用正常 App 替换根 widget，失败则刷新错误信息
  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await AppDatabase.init();
      runApp(const ProviderScope(child: SearchReaderApp()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _retrying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '应用启动失败',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '数据库初始化失败，暂时无法进入应用。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  // 错误详情可长按选中复制，便于反馈与排查
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _error.toString(),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _retrying ? null : _retry,
                    icon: _retrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_retrying ? '重试中…' : '重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
