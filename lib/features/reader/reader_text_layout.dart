// 阅读排版环境：测量与展示共用系统缩放、语言和行高行为，避免分页容量发生偏差。
import 'package:flutter/widgets.dart';

@immutable
class ReaderTextLayout {
  final TextScaler textScaler;
  final TextDirection textDirection;
  final Locale? locale;
  final TextHeightBehavior? textHeightBehavior;
  final TextWidthBasis textWidthBasis;

  const ReaderTextLayout({
    this.textScaler = TextScaler.noScaling,
    this.textDirection = TextDirection.ltr,
    this.locale,
    this.textHeightBehavior,
    this.textWidthBasis = TextWidthBasis.parent,
  });

  factory ReaderTextLayout.of(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    return ReaderTextLayout(
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: defaults.textHeightBehavior,
      textWidthBasis: defaults.textWidthBasis,
    );
  }

  TextPainter createPainter(String text, TextStyle style, double width) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: textScaler,
      textDirection: textDirection,
      locale: locale,
      textHeightBehavior: textHeightBehavior,
      textWidthBasis: textWidthBasis,
    )..layout(maxWidth: width);
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderTextLayout &&
      textScaler == other.textScaler &&
      textDirection == other.textDirection &&
      locale == other.locale &&
      textHeightBehavior == other.textHeightBehavior &&
      textWidthBasis == other.textWidthBasis;

  @override
  int get hashCode => Object.hash(
    textScaler,
    textDirection,
    locale,
    textHeightBehavior,
    textWidthBasis,
  );
}
