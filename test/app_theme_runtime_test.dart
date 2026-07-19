import 'dart:convert';

import 'package:agent_battery_flutter/app.dart';
import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:agent_battery_flutter/ui/screens/home_screen.dart';
import 'package:agent_battery_flutter/ui/window_layout_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stateKey = 'agent_battery_state_v1';

class _MemorySecureKeyStore implements SecureKeyStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

const _palette = ThemePalette(
  primary: 0xff102030,
  secondary: 0xff406080,
  stage: 0xff203040,
  content: 0xff202122,
  pageBackground: 0xff303132,
  card: 0xff404142,
  dialogBackground: 0xff505152,
  cardAlt: 0xffe0e1e2,
  text: 0xff101112,
  mutedText: 0xff505152,
  onStage: 0xffffffff,
  outline: 0xffa0a1a2,
  success: 0xff208060,
  error: 0xffb03040,
  statusIdle: 0xff707172,
  shadow: 0xff000000,
);

CustomTheme _theme({
  required String id,
  required ThemeLayout layout,
  String? background,
  BackgroundImageFit backgroundImageFit = BackgroundImageFit.cover,
  BackgroundImageAlignment backgroundImageAlignment =
      BackgroundImageAlignment.center,
  double backgroundImageOpacity = 1,
  DashboardLayoutMode dashboardLayoutMode = DashboardLayoutMode.standard,
  DashboardDensity dashboardDensity = DashboardDensity.comfortable,
}) => CustomTheme(
  id: id,
  name: 'Runtime',
  layout: layout,
  palette: _palette,
  cardRadius: 18,
  controlRadius: 12,
  contentRadius: 24,
  shadowOpacity: .3,
  stageOverlayOpacity: .4,
  backgroundImageFileName: background,
  backgroundImageFit: backgroundImageFit,
  backgroundImageAlignment: backgroundImageAlignment,
  backgroundImageOpacity: backgroundImageOpacity,
  dashboardLayoutMode: dashboardLayoutMode,
  dashboardDensity: dashboardDensity,
);

Future<BatteryController> _controller(CustomTheme theme) async {
  SharedPreferences.setMockInitialValues({
    _stateKey: jsonEncode(
      AppSnapshot(
        customThemes: [theme],
        themeReference: ThemeReference.custom(theme.id),
      ).toJson(),
    ),
  });
  final controller = BatteryController(
    storage: StorageService(keyStore: _MemorySecureKeyStore()),
    api: ApiClient(),
  );
  await controller.initialize(refreshOnStart: false);
  return controller;
}

void main() {
  testWidgets(
    'custom dashboard applies its material primary color and compact policy',
    (tester) async {
      final controller = await _controller(
        _theme(
          id: 'a1b2c3d4-e5f6-4789-8123-456789abcdef',
          layout: ThemeLayout.dashboard,
        ),
      );
      await tester.pumpWidget(
        AgentBatteryApp(controller: controller, initializeServices: false),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).colorScheme.primary,
        const Color(0xff102030),
      );
      expect(controller.resolvedTheme.layout, WindowLayoutPolicy.compact);
      expect(find.byKey(const Key('custom-stage-wrapper')), findsNothing);
    },
  );

  testWidgets(
    'custom dashboard keeps page and data-panel backgrounds independent',
    (tester) async {
      final controller = await _controller(
        _theme(
          id: 'a2b2c3d4-e5f6-4789-8123-456789abcdef',
          layout: ThemeLayout.dashboard,
        ),
      );
      await tester.pumpWidget(
        AgentBatteryApp(controller: controller, initializeServices: false),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      final page = tester.widget<ColoredBox>(
        find.byKey(const Key('custom-dashboard-page-background')),
      );
      expect(page.color, const Color(0xff303132));
      final materialTheme = Theme.of(tester.element(find.byType(HomeScreen)));
      expect(materialTheme.scaffoldBackgroundColor, const Color(0xff303132));
      expect(
        materialTheme.appBarTheme.backgroundColor,
        const Color(0xff303132),
      );
      final panel = tester.widget<Container>(
        find.byKey(const Key('custom-dashboard-standard')),
      );
      final gradient = (panel.decoration! as BoxDecoration).gradient!;
      expect(gradient.colors.first, const Color(0xff202122));
      expect(
        gradient.colors.first,
        isNot(materialTheme.scaffoldBackgroundColor),
      );
    },
  );

  testWidgets(
    'custom card and dialog backgrounds remain independent at runtime',
    (tester) async {
      final controller = await _controller(
        _theme(
          id: 'a3b2c3d4-e5f6-4789-8123-456789abcdef',
          layout: ThemeLayout.dashboard,
        ),
      );
      await tester.pumpWidget(
        AgentBatteryApp(controller: controller, initializeServices: false),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      final materialTheme = Theme.of(tester.element(find.byType(HomeScreen)));
      expect(materialTheme.cardTheme.color, const Color(0xff404142));
      expect(
        materialTheme.dialogTheme.backgroundColor,
        const Color(0xff505152),
      );
      expect(
        materialTheme.cardTheme.color,
        isNot(materialTheme.dialogTheme.backgroundColor),
      );
    },
  );

  testWidgets('custom stage uses the stage policy and stage wrapper', (
    tester,
  ) async {
    final controller = await _controller(
      _theme(
        id: 'b1b2c3d4-e5f6-4789-8123-456789abcdef',
        layout: ThemeLayout.stage,
      ),
    );
    await tester.pumpWidget(
      AgentBatteryApp(controller: controller, initializeServices: false),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));

    expect(controller.resolvedTheme.layout, WindowLayoutPolicy.mikuStage);
    expect(find.byKey(const Key('custom-stage-wrapper')), findsOneWidget);
  });

  testWidgets(
    'custom focus dashboard exposes its compact presentation markers',
    (tester) async {
      final controller = await _controller(
        _theme(
          id: 'b2b2c3d4-e5f6-4789-8123-456789abcdef',
          layout: ThemeLayout.dashboard,
          dashboardLayoutMode: DashboardLayoutMode.focus,
          dashboardDensity: DashboardDensity.compact,
        ),
      );
      await tester.pumpWidget(
        AgentBatteryApp(controller: controller, initializeServices: false),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(find.byKey(const Key('custom-dashboard-focus')), findsOneWidget);
      expect(
        find.byKey(const Key('custom-dashboard-density-compact')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'custom stage applies focus presentation rather than falling back to standard',
    (tester) async {
      final controller = await _controller(
        _theme(
          id: 'b3b2c3d4-e5f6-4789-8123-456789abcdef',
          layout: ThemeLayout.stage,
          dashboardLayoutMode: DashboardLayoutMode.focus,
          dashboardDensity: DashboardDensity.compact,
        ),
      );
      await tester.pumpWidget(
        AgentBatteryApp(controller: controller, initializeServices: false),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      expect(find.byKey(const Key('custom-stage-wrapper')), findsOneWidget);
      expect(find.byKey(const Key('custom-dashboard-focus')), findsOneWidget);
      expect(
        find.byKey(const Key('custom-dashboard-focus-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('custom-dashboard-density-compact')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a missing managed stage background falls back without exception',
    (tester) async {
      final controller = await _controller(
        _theme(
          id: 'c1b2c3d4-e5f6-4789-8123-456789abcdef',
          layout: ThemeLayout.stage,
          background: 'missing.png',
        ),
      );
      await tester.pumpWidget(
        AgentBatteryApp(controller: controller, initializeServices: false),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.pump();

      expect(find.byKey(const Key('custom-stage-wrapper')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('builtins continue to resolve and render their original stage', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller(
      _theme(
        id: 'd1b2c3d4-e5f6-4789-8123-456789abcdef',
        layout: ThemeLayout.dashboard,
      ),
    );
    await controller.selectTheme(AppTheme.miku);
    await tester.pumpWidget(
      AgentBatteryApp(controller: controller, initializeServices: false),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));

    expect(controller.resolvedTheme.tokens.kind, AppTheme.miku);
    expect(find.byKey(const Key('miku-stage-wide')), findsOneWidget);
  });

  testWidgets(
    'saved custom theme appears in the switch menu and can be applied',
    (tester) async {
      final theme = _theme(
        id: 'c1b2c3d4-e5f6-4789-8123-456789abcdef',
        layout: ThemeLayout.stage,
      );
      SharedPreferences.setMockInitialValues({
        _stateKey: jsonEncode(
          AppSnapshot(
            customThemes: [theme],
            themeReference: ThemeReference.builtin(AppTheme.miku),
          ).toJson(),
        ),
      });
      final controller = BatteryController(
        storage: StorageService(keyStore: _MemorySecureKeyStore()),
        api: ApiClient(),
      );
      await controller.initialize(refreshOnStart: false);
      await tester.pumpWidget(
        AgentBatteryApp(controller: controller, initializeServices: false),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      await tester.tap(find.byTooltip('切换主题'));
      await tester.pumpAndSettle();
      expect(find.text('自定义主题'), findsOneWidget);
      expect(find.text('Runtime'), findsOneWidget);

      await tester.tap(find.text('Runtime'));
      await tester.pumpAndSettle();
      expect(controller.themeReference, ThemeReference.custom(theme.id));
    },
  );
}
