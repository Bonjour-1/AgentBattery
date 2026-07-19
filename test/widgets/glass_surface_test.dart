import 'dart:ui';

import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/ui/theme/app_theme_tokens.dart';
import 'package:agent_battery_flutter/ui/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(AppTheme theme) => MaterialApp(
  theme: AppThemeTokens.forTheme(theme).materialTheme(),
  home: Scaffold(
    body: GlassSurface(
      child: const SizedBox(width: 120, height: 80, child: Text('surface')),
    ),
  ),
);

void main() {
  testWidgets('glass theme surfaces use a clipped backdrop blur', (
    tester,
  ) async {
    await tester.pumpWidget(_host(AppTheme.glass));

    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter, isA<ImageFilter>());
  });

  testWidgets('non-glass themes keep their existing unblurred surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(_host(AppTheme.miku));

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
