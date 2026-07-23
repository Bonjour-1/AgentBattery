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

  testWidgets('an opted-in custom theme uses a clipped backdrop blur', (
    tester,
  ) async {
    final theme = CustomTheme(
      id: '1b4e28ba-2fa1-11d2-883f-0016d3cca427',
      name: '风景',
      layout: ThemeLayout.stage,
      palette: const ThemePalette(
        primary: 0xff010203,
        secondary: 0xff040506,
        stage: 0xff070809,
        content: 0xff101112,
        pageBackground: 0xff121314,
        card: 0xff131415,
        dialogBackground: 0xff141516,
        cardAlt: 0xff151617,
        text: 0xfff7f8f9,
        mutedText: 0xffd7d8d9,
        onStage: 0xffffffff,
        outline: 0xff202122,
        success: 0xff252627,
        error: 0xff28292a,
        statusIdle: 0xff2b2c2d,
        shadow: 0xff000000,
      ),
      cardRadius: 20,
      controlRadius: 14,
      contentRadius: 28,
      shadowOpacity: .2,
      stageOverlayOpacity: .2,
      useGlassSurface: true,
      useLiquidGlassSurface: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeTokens.custom(theme).materialTheme(),
        home: Scaffold(
          body: GlassSurface(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x99112233), Color(0x66556677)],
            ),
            child: const SizedBox(),
          ),
        ),
      ),
    );

    final gradients = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(GlassSurface),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>();
    expect(
      gradients,
      contains(
        isA<LinearGradient>()
            .having((gradient) => gradient.begin, 'begin', Alignment.centerLeft)
            .having((gradient) => gradient.end, 'end', Alignment.bottomRight),
      ),
    );
    expect(
      (tester
                  .widget<DecoratedBox>(
                    find.byKey(const Key('liquid-glass-refraction')),
                  )
                  .decoration
              as BoxDecoration)
          .gradient!
          .colors
          .first
          .a,
      closeTo(.33, .01),
    );
    expect(find.byKey(const Key('liquid-glass-rim-light')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('liquid-glass reflection follows the pointer', (tester) async {
    final theme = CustomTheme(
      id: 'ce45f0ab-4e47-4bd9-8a0d-b92700d4b8fa',
      name: 'Liquid motion',
      layout: ThemeLayout.dashboard,
      palette: const ThemePalette(
        primary: 0xff010203,
        secondary: 0xff040506,
        stage: 0xff070809,
        content: 0xff101112,
        pageBackground: 0xff121314,
        card: 0xff131415,
        dialogBackground: 0xff141516,
        cardAlt: 0xff151617,
        text: 0xfff7f8f9,
        mutedText: 0xffd7d8d9,
        onStage: 0xffffffff,
        outline: 0xff202122,
        success: 0xff252627,
        error: 0xff28292a,
        statusIdle: 0xff2b2c2d,
        shadow: 0xff000000,
      ),
      cardRadius: 20,
      controlRadius: 14,
      contentRadius: 28,
      shadowOpacity: .2,
      stageOverlayOpacity: .2,
      useGlassSurface: true,
      useLiquidGlassSurface: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeTokens.custom(theme).materialTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 120,
              child: GlassSurface(child: const SizedBox.expand()),
            ),
          ),
        ),
      ),
    );

    final reflection = find.byKey(const Key('liquid-glass-pointer-reflection'));
    expect(reflection, findsOneWidget);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(-10, -10));
    await pointer.moveTo(tester.getTopLeft(reflection) + const Offset(220, 90));
    await tester.pump(const Duration(milliseconds: 180));

    final gradient =
        (tester.widget<AnimatedContainer>(reflection).decoration
                    as BoxDecoration)
                .gradient!
            as RadialGradient;
    final position = gradient.center.resolve(TextDirection.ltr);
    expect(position.x, greaterThan(0));
    expect(position.y, greaterThan(0));
  });

  testWidgets(
    'a liquid-glass surface can keep a custom gradient without blur',
    (tester) async {
      final theme = CustomTheme(
        id: '5e2e7d5f-1a2b-4cfb-bf42-cddbf6d5c653',
        name: '风景',
        layout: ThemeLayout.stage,
        palette: const ThemePalette(
          primary: 0xff010203,
          secondary: 0xff040506,
          stage: 0xff070809,
          content: 0xff101112,
          pageBackground: 0xff121314,
          card: 0xff131415,
          dialogBackground: 0xff141516,
          cardAlt: 0xff151617,
          text: 0xfff7f8f9,
          mutedText: 0xffd7d8d9,
          onStage: 0xffffffff,
          outline: 0xff202122,
          success: 0xff252627,
          error: 0xff28292a,
          statusIdle: 0xff2b2c2d,
          shadow: 0xff000000,
        ),
        cardRadius: 20,
        controlRadius: 14,
        contentRadius: 28,
        shadowOpacity: .2,
        stageOverlayOpacity: .2,
        useGlassSurface: true,
        useLiquidGlassSurface: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeTokens.custom(theme).materialTheme(),
          home: Scaffold(
            body: GlassSurface(blur: false, child: const SizedBox()),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
    },
  );
  testWidgets('non-glass themes keep their existing unblurred surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(_host(AppTheme.miku));

    expect(find.byType(BackdropFilter), findsNothing);
  });
}
