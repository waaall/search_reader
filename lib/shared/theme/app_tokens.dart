// 设计 token：全 app 统一引用的间距、圆角与动效时长数值。
// 颜色与组件样式属于主题层，由 AppTheme 经 flex_color_scheme 生成；
// 此文件只收纳 widget 代码里直接写出的数值，避免散落硬编码。

// 间距阶梯
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

// 圆角阶梯（与主题 defaultRadius 取同一套值）
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

// 动效时长：统一微动画节奏
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
}
