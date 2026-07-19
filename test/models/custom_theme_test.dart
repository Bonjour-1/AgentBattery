import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:flutter_test/flutter_test.dart';

const _themeId = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';

const _palette = ThemePalette(
  primary: 0xff15968e,
  secondary: 0xffff8fab,
  stage: 0xff0d5753,
  content: 0xffe9fffd,
  pageBackground: 0xffe9fffd,
  card: 0xfff3fffe,
  dialogBackground: 0xfff3fffe,
  cardAlt: 0xffddf8f5,
  text: 0xff123f3d,
  mutedText: 0xff557a77,
  onStage: 0xffffffff,
  outline: 0xffb6e4df,
  success: 0xff13867f,
  error: 0xffc34c70,
  statusIdle: 0xff687b79,
  shadow: 0xff0d5c57,
);

final _customTheme = CustomTheme(
  id: _themeId,
  name: '  午夜青绿  ',
  layout: ThemeLayout.stage,
  palette: _palette,
  cardRadius: 24,
  controlRadius: 16,
  contentRadius: 34,
  shadowOpacity: .45,
  stageOverlayOpacity: .28,
  backgroundImageFileName: '1b4e28ba-background.webp',
);

void main() {
  group('CustomTheme', () {
    test(
      'migrates legacy page and dialog backgrounds without losing surfaces',
      () {
        final legacyPaletteJson = _palette.toJson()
          ..remove('page_background')
          ..remove('dialog_background');

        final restored = ThemePalette.fromJson(legacyPaletteJson);

        expect(restored.pageBackground, _palette.content);
        expect(restored.dialogBackground, _palette.card);
        expect(restored.cardAlt, _palette.cardAlt);
      },
    );

    test('round trips and copies independent semantic backgrounds', () {
      final palette = _palette.copyWith(
        pageBackground: 0xff313233,
        dialogBackground: 0xff343536,
      );

      expect(palette.content, _palette.content);
      expect(palette.card, _palette.card);
      expect(palette.cardAlt, _palette.cardAlt);
      expect(palette.toJson()['page_background'], 0xff313233);
      expect(palette.toJson()['dialog_background'], 0xff343536);
      expect(ThemePalette.fromJson(palette.toJson()), palette);
      expect(palette, isNot(_palette));
      expect(palette.hashCode, isNot(_palette.hashCode));
    });

    test('rejects malformed explicit split background values', () {
      for (final key in ['page_background', 'dialog_background']) {
        expect(
          () => ThemePalette.fromJson({..._palette.toJson(), key: null}),
          throwsArgumentError,
        );
        expect(
          () => ThemePalette.fromJson({..._palette.toJson(), key: 'invalid'}),
          throwsArgumentError,
        );
      }
    });

    test('rejects partially migrated split backgrounds', () {
      for (final missingKey in ['page_background', 'dialog_background']) {
        final partialJson = _palette.toJson()..remove(missingKey);

        expect(() => ThemePalette.fromJson(partialJson), throwsArgumentError);
      }
    });

    test('round trips every persisted customization field', () {
      final restored = CustomTheme.fromJson(_customTheme.toJson());

      expect(restored, _customTheme);
      expect(restored.name, '午夜青绿');
      expect(restored.backgroundImageFileName, '1b4e28ba-background.webp');
    });

    test(
      'persists background fit, alignment, and opacity with old JSON defaults',
      () {
        final adjusted = _customTheme.copyWith(
          backgroundImageFit: BackgroundImageFit.contain,
          backgroundImageAlignment: BackgroundImageAlignment.right,
          backgroundImageOpacity: .65,
        );

        expect(CustomTheme.fromJson(adjusted.toJson()), adjusted);
        expect(
          CustomTheme.fromJson(_customTheme.toJson()).backgroundImageFit,
          BackgroundImageFit.cover,
        );
        expect(
          CustomTheme.fromJson(_customTheme.toJson()).backgroundImageAlignment,
          BackgroundImageAlignment.center,
        );
        expect(
          CustomTheme.fromJson(_customTheme.toJson()).backgroundImageOpacity,
          1,
        );
        final glass = _customTheme.copyWith(
          useGlassSurface: true,
          useLiquidGlassSurface: true,
        );
        final legacy = Map<String, Object?>.from(_customTheme.toJson())
          ..remove('use_glass_surface');
        expect(glass.useGlassSurface, isTrue);
        expect(CustomTheme.fromJson(glass.toJson()), glass);
        expect(CustomTheme.fromJson(legacy).useGlassSurface, isFalse);
        expect(
          () => adjusted.copyWith(backgroundImageOpacity: 1.01),
          throwsArgumentError,
        );
      },
    );

    test(
      'persists optional layered gradients and defaults old JSON to solid',
      () {
        final layered = _customTheme.copyWith(
          stageGradientSecondary: 0xff112233,
          stageGradientDirection: GradientDirection.diagonal,
          contentGradientSecondary: 0xff445566,
          contentGradientDirection: GradientDirection.leftRight,
          cardGradientSecondary: 0xff778899,
          cardGradientDirection: GradientDirection.topBottom,
        );
        final legacy = Map<String, Object?>.from(_customTheme.toJson())
          ..remove('stage_gradient_secondary')
          ..remove('stage_gradient_direction')
          ..remove('content_gradient_secondary')
          ..remove('content_gradient_direction')
          ..remove('card_gradient_secondary')
          ..remove('card_gradient_direction');

        expect(CustomTheme.fromJson(layered.toJson()), layered);
        expect(CustomTheme.fromJson(legacy).stageGradientSecondary, isNull);
        expect(
          CustomTheme.fromJson(legacy).stageGradientDirection,
          GradientDirection.topBottom,
        );
        expect(
          () => _customTheme.copyWith(cardGradientSecondary: -1),
          throwsArgumentError,
        );
        expect(
          () => CustomTheme.fromJson({
            ..._customTheme.toJson(),
            'stage_gradient_direction': 'freeform',
          }),
          throwsArgumentError,
        );
      },
    );

    test(
      'defaults legacy JSON to the standard comfortable dashboard presentation',
      () {
        final legacy = Map<String, Object?>.from(_customTheme.toJson())
          ..remove('dashboard_layout_mode')
          ..remove('dashboard_density');
        final focusedCompact = _customTheme.copyWith(
          dashboardLayoutMode: DashboardLayoutMode.focus,
          dashboardDensity: DashboardDensity.compact,
        );

        final restored = CustomTheme.fromJson(legacy);
        expect(restored.dashboardLayoutMode, DashboardLayoutMode.standard);
        expect(restored.dashboardDensity, DashboardDensity.comfortable);
        expect(CustomTheme.fromJson(focusedCompact.toJson()), focusedCompact);
      },
    );

    test(
      'rejects invalid ID, blank or overlong name, invalid colors and bounds',
      () {
        expect(
          () => _customTheme.copyWith(id: 'not-a-uuid'),
          throwsArgumentError,
        );
        expect(() => _customTheme.copyWith(name: '   '), throwsArgumentError);
        expect(
          () => _customTheme.copyWith(name: 'x' * 33),
          throwsArgumentError,
        );
        expect(() => _palette.copyWith(primary: -1), throwsArgumentError);
        expect(
          () => _palette.copyWith(primary: 0x100000000),
          throwsArgumentError,
        );
        expect(
          () => _customTheme.copyWith(cardRadius: -0.1),
          throwsArgumentError,
        );
        expect(
          () => _customTheme.copyWith(shadowOpacity: 1.01),
          throwsArgumentError,
        );
        expect(
          () => _customTheme.copyWith(stageOverlayOpacity: -0.01),
          throwsArgumentError,
        );
      },
    );

    test('accepts only a managed background basename', () {
      for (final invalid in [
        '/absolute.png',
        r'C:\\pictures\\background.png',
        '../background.png',
        'nested/background.png',
        '',
      ]) {
        expect(
          () => _customTheme.copyWith(backgroundImageFileName: invalid),
          throwsArgumentError,
        );
      }
    });
  });

  group('ThemeReference', () {
    test('round trips builtin and custom references', () {
      const builtin = ThemeReference.builtin(AppTheme.mita);
      const custom = ThemeReference.custom(_themeId);

      expect(ThemeReference.fromJson(builtin.toJson()), builtin);
      expect(ThemeReference.fromJson(custom.toJson()), custom);
    });
  });

  group('AppSnapshot custom-theme migration', () {
    test('new fields take precedence and custom theme survives round trip', () {
      final snapshot = AppSnapshot(
        themeReference: ThemeReference.custom(_themeId),
        customThemes: [_customTheme],
      );

      final stored = snapshot.toJson();
      final restored = AppSnapshot.fromJson(stored);

      expect(stored['theme_reference'], _customThemeReferenceJson);
      expect(stored['theme'], isNull);
      expect(restored.themeReference, const ThemeReference.custom(_themeId));
      expect(restored.customThemes, [_customTheme]);
      expect(restored.theme, AppTheme.miku);
    });

    test('migrates every old builtin key without losing old snapshots', () {
      for (final theme in AppTheme.values) {
        final restored = AppSnapshot.fromJson({
          'theme': theme.name,
          'providers': {
            'deepseek': {'last_balance': 8.5},
          },
        });

        expect(restored.themeReference, ThemeReference.builtin(theme));
        expect(restored.theme, theme);
        expect(restored.customThemes, isEmpty);
        expect(restored.providers['deepseek']!.lastBalance, 8.5);
        expect(restored.toJson()['theme'], theme.name);
        expect(restored.toJson().containsKey('custom_themes'), isTrue);
      }
    });

    test(
      'falls back safely when active custom ID is unknown or theme is corrupt',
      () {
        final unknown = AppSnapshot.fromJson({
          'theme_reference': _customThemeReferenceJson,
          'custom_themes': const [],
        });
        final corrupt = AppSnapshot.fromJson({
          'theme_reference': _customThemeReferenceJson,
          'custom_themes': [
            {
              ..._customTheme.toJson(),
              'palette': {..._palette.toJson(), 'primary': -1},
            },
          ],
        });

        expect(
          unknown.themeReference,
          const ThemeReference.builtin(AppTheme.miku),
        );
        expect(
          corrupt.themeReference,
          const ThemeReference.builtin(AppTheme.miku),
        );
        expect(corrupt.customThemes, isEmpty);
      },
    );
  });
}

const _customThemeReferenceJson = {
  'kind': 'custom',
  'custom_theme_id': _themeId,
};
