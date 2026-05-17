import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

// 本地化入口扩展：统一通过 context.l10n 读取当前语言文案。
extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
