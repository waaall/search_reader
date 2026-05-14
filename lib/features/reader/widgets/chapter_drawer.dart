import 'package:flutter/material.dart';

import '../../../domain/chapter.dart';

// 章节目录抽屉
class ChapterDrawer extends StatelessWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final void Function(int chapterIndex) onJump;

  const ChapterDrawer({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('目录',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: chapters.length,
                itemBuilder: (_, i) {
                  final c = chapters[i];
                  final isCurrent = i == currentIndex;
                  return ListTile(
                    dense: true,
                    title: Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        fontWeight: isCurrent ? FontWeight.bold : null,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onJump(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
