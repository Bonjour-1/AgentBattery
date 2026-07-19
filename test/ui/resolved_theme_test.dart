import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/ui/theme/resolved_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _themeId = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';

final _palette = const ThemePalette(
  primary: 0xff010203,
  secondary: 0xff040506,
  stage: 0xff070809,
  content: 0xff101112,
  pageBackground: 0xff313233,
  card: 0xff131415,
  dialogBackground: 0xff343536,
  cardAlt: 0xff161718,
  text: 0xff191a1b,
  mutedText: 0xff1c1d1e,
  onStage: 0xff1f2021,
  outline: 0xff222324,
  success: 0xff252627,
  error: 0xff28292a,
  statusIdle: 0xff2b2c2d,
  shadow: 0xff2e2f30,
);

CustomTheme _customTheme(ThemeLayout layout) => CustomTheme(
  id: _themeId,
  name: 'Custom night',
  layout: layout,
  palette: _palette,
  cardRadius: 11,
  controlRadius: 12,
  contentRadius: 13,
  shadowOpacity: .4,
  stageOverlayOpacity: .3,
);

void main() {
  test('custom theme maps every palette color and radius into tokens', () {
    final resolved = ResolvedTheme.custom(_customTheme(ThemeLayout.dashboard));
    final tokens = resolved.tokens;

    expect(resolved.name, 'Custom night');
    expect(tokens.pageBackground, const Color(0xff313233));
    expect(tokens.surface, const Color(0xff131415));
    expect(tokens.dialogBackground, const Color(0xff343536));
    expect(tokens.surfaceAlt, const Color(0xff161718));
    expect(tokens.primary, const Color(0xff010203));
    expect(tokens.secondary, const Color(0xff040506));
    expect(tokens.text, const Color(0xff191a1b));
    expect(tokens.mutedText, const Color(0xff1c1d1e));
    expect(tokens.onStage, const Color(0xff1f2021));
    expect(tokens.outline, const Color(0xff222324));
    expect(tokens.success, const Color(0xff252627));
    expect(tokens.error, const Color(0xff28292a));
    expect(tokens.statusIdle, const Color(0xff2b2c2d));
    expect(tokens.shadow, const Color(0xff2e2f30));
    expect(tokens.stageGradient.colors, [
      const Color(0xff070809),
      const Color(0xff070809),
    ]);
    expect(tokens.contentGradient.colors, [
      const Color(0xff101112),
      const Color(0xff101112),
    ]);
    expect(tokens.cardGradient.colors, [
      const Color(0xff131415),
      const Color(0xff131415),
    ]);
    expect(tokens.cardRadius, 11);
    expect(tokens.controlRadius, 12);
    expect(tokens.contentRadius, 13);
  });

  test(
    'material theme keeps page card dialog and input surfaces independent',
    () {
      final tokens = ResolvedTheme.custom(
        _customTheme(ThemeLayout.dashboard),
      ).tokens;
      final materialTheme = tokens.materialTheme();

      expect(materialTheme.scaffoldBackgroundColor, tokens.pageBackground);
      expect(materialTheme.appBarTheme.backgroundColor, tokens.pageBackground);
      expect(materialTheme.cardTheme.color, tokens.surface);
      expect(
        materialTheme.dialogTheme.backgroundColor,
        tokens.dialogBackground,
      );
      expect(materialTheme.inputDecorationTheme.fillColor, tokens.surfaceAlt);
    },
  );

  test('custom layered gradients resolve colors and safe directions', () {
    final tokens = ResolvedTheme.custom(
      _customTheme(ThemeLayout.stage).copyWith(
        stageGradientSecondary: 0xff313233,
        stageGradientDirection: GradientDirection.diagonal,
        contentGradientSecondary: 0xff414243,
        contentGradientDirection: GradientDirection.leftRight,
        cardGradientSecondary: 0xff515253,
      ),
    ).tokens;

    expect(tokens.stageGradient.colors, [
      const Color(0xff070809),
      const Color(0xff313233),
    ]);
    expect(tokens.stageGradient.begin, Alignment.topLeft);
    expect(tokens.stageGradient.end, Alignment.bottomRight);
    expect(tokens.contentGradient.begin, Alignment.centerLeft);
    expect(tokens.contentGradient.end, Alignment.centerRight);
    expect(tokens.cardGradient.colors, [
      const Color(0xff131415),
      const Color(0xff515253),
    ]);
    expect(tokens.cardGradient.colors, hasLength(2));
  });

  test('dashboard custom theme resolves to compact layout', () {
    final resolved = ResolvedTheme.custom(_customTheme(ThemeLayout.dashboard));

    expect(resolved.layout.size, const Size(680, 800));
    expect(resolved.layout.minimumSize, const Size(620, 720));
  });

  test('stage custom theme resolves to stage layout', () {
    final resolved = ResolvedTheme.custom(_customTheme(ThemeLayout.stage));

    expect(resolved.layout.size, const Size(1320, 760));
    expect(resolved.layout.minimumSize, const Size(1080, 680));
  });

  test('builtin themes retain their tokens and layout policies', () {
    for (final theme in AppTheme.values) {
      final resolved = ResolvedTheme.builtin(theme);

      expect(resolved.tokens, same(resolved.tokens));
      expect(resolved.tokens.kind, theme);
      expect(resolved.layout, isNotNull);
    }
  });
}
