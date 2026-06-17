// 内容状态切换组件：把加载、空态、列表等状态的切换统一成轻微淡入上滑。

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class AppAnimatedSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  const AppAnimatedSwitcher({
    super.key,
    required this.child,
    this.duration = AppMotion.normal,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeInOut,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: AppMotion.easeOut,
          reverseCurve: AppMotion.easeInOut,
        );
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(fade);

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: child,
    );
  }
}
