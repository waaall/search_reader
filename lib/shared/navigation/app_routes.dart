// 页面转场统一入口：使用轻量淡入和小幅上滑，让不同页面跳转保持一致且克制。

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

Route<T> appRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: AppMotion.normal,
    reverseTransitionDuration: AppMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.easeOut,
        reverseCurve: AppMotion.easeInOut,
      );
      final offset = Tween<Offset>(
        begin: const Offset(0, 0.025),
        end: Offset.zero,
      ).animate(curved);

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: offset, child: child),
      );
    },
  );
}
