// 字符与滚动坐标转换：使用正文实际布局，避免按字符比例估算造成搜索和进度偏移。
import 'package:flutter/rendering.dart';

abstract final class ReaderTextPosition {
  static RenderParagraph? _paragraphIn(RenderObject object) {
    if (object is RenderParagraph) return object;
    RenderParagraph? paragraph;
    object.visitChildren((child) => paragraph ??= _paragraphIn(child));
    return paragraph;
  }

  static double? verticalOffsetForCharacter(RenderBox box, int charOffset) {
    final paragraph = _paragraphIn(box);
    if (paragraph == null || !paragraph.hasSize) return null;
    final offset = charOffset.clamp(0, paragraph.text.toPlainText().length);
    final caret = paragraph.getOffsetForCaret(
      TextPosition(offset: offset),
      Rect.zero,
    );
    return paragraph.localToGlobal(caret, ancestor: box).dy;
  }

  static int? characterAtVerticalOffset(RenderBox box, double verticalOffset) {
    final paragraph = _paragraphIn(box);
    if (paragraph == null || !paragraph.hasSize) return null;
    final local = paragraph.globalToLocal(
      box.localToGlobal(Offset(0, verticalOffset)),
    );
    // 进度取可见行的逻辑起点；从右向左排版时应从右边缘取字。
    final x = paragraph.textDirection == TextDirection.rtl
        ? paragraph.size.width
        : 0.0;
    return paragraph.getPositionForOffset(Offset(x, local.dy)).offset;
  }
}
