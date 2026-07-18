import '../../models/custom_theme.dart';
import '../window_layout_policy.dart';
import 'app_theme_tokens.dart';

class ResolvedTheme {
  const ResolvedTheme._({
    required this.name,
    required this.tokens,
    required this.layout,
  });

  final String name;
  final AppThemeTokens tokens;
  final WindowLayoutPolicy layout;

  factory ResolvedTheme.builtin(AppTheme theme) {
    final tokens = AppThemeTokens.forTheme(theme);
    return ResolvedTheme._(
      name: tokens.name,
      tokens: tokens,
      layout: WindowLayoutPolicy.forTheme(theme),
    );
  }

  factory ResolvedTheme.custom(CustomTheme theme) => ResolvedTheme._(
    name: theme.name,
    tokens: AppThemeTokens.custom(theme),
    layout: WindowLayoutPolicy.forCustomLayout(theme.layout),
  );
}
