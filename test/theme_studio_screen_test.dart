import 'dart:convert';
import 'dart:io';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/services/theme_package_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:agent_battery_flutter/ui/screens/home_screen.dart';
import 'package:agent_battery_flutter/ui/screens/theme_studio_screen.dart';
import 'package:agent_battery_flutter/ui/theme/app_theme_tokens.dart';
import 'package:file_selector/file_selector.dart';
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

Future<BatteryController> _controller() async {
  SharedPreferences.setMockInitialValues({
    _stateKey: jsonEncode(const AppSnapshot().toJson()),
  });
  final controller = BatteryController(
    storage: StorageService(keyStore: _MemorySecureKeyStore()),
    api: ApiClient(),
  );
  await controller.initialize(refreshOnStart: false);
  return controller;
}

Widget _host(BatteryController controller, Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(1600, 900)),
  child: MaterialApp(
    theme: controller.resolvedTheme.tokens.materialTheme(),
    home: child,
  ),
);

void main() {
  testWidgets('home theme menu exposes the theme studio', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, HomeScreen(controller: controller)),
    );

    await tester.tap(find.byTooltip('切换主题'));
    await tester.pump();

    expect(find.text('主题工作台'), findsOneWidget);
  });

  testWidgets('new theme creates an editable draft and previews its changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );

    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-new-button')),
    );
    await tester.tap(find.byKey(const Key('theme-studio-new-button')));
    await tester.pump();
    expect(find.text('编辑草稿'), findsOneWidget);
    expect(find.byKey(const Key('theme-background-fit-field')), findsOneWidget);
    expect(
      find.byKey(const Key('theme-background-alignment-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('theme-background-opacity-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('theme-advanced-gradients-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('theme-dashboard-layout-mode')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('theme-dashboard-density')), findsOneWidget);
    final layoutField = tester
        .widget<DropdownButtonFormField<DashboardLayoutMode>>(
          find.byKey(const Key('theme-dashboard-layout-mode')),
        );
    layoutField.onChanged!(DashboardLayoutMode.focus);
    final densityField = tester
        .widget<DropdownButtonFormField<DashboardDensity>>(
          find.byKey(const Key('theme-dashboard-density')),
        );
    densityField.onChanged!(DashboardDensity.compact);
    await tester.pump();
    expect(
      find.byKey(const Key('theme-preview-density-compact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('theme-preview-focus-summary')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('theme-advanced-gradients-section')),
    );
    await tester.tap(find.byKey(const Key('theme-advanced-gradients-section')));
    await tester.pump();
    expect(
      find.byKey(const Key('theme-stage-gradient-enabled')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('theme-stage-gradient-direction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('theme-content-gradient-enabled')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('theme-card-gradient-enabled')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('theme-name-field')), '我的霓虹');
    await tester.ensureVisible(
      find.byKey(const Key('theme-color-picker-theme-color-primary')),
    );
    await tester.tap(
      find.byKey(const Key('theme-color-picker-theme-color-primary')),
    );
    await tester.pump();
    await tester.tap(find.text('高级输入（十六进制）'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('theme-color-primary-hex')),
      'FF112233',
    );
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump();
    final themeLayoutField = tester
        .widget<DropdownButtonFormField<ThemeLayout>>(
          find.byType(DropdownButtonFormField<ThemeLayout>),
        );
    themeLayoutField.onChanged!(ThemeLayout.dashboard);
    await tester.pump();
    expect(
      find.byKey(const Key('theme-preview-dashboard-layout')),
      findsOneWidget,
    );
    final dashboardCanvas = tester.widget<SizedBox>(
      find.byKey(const Key('theme-preview-canvas')),
    );
    expect(dashboardCanvas.width, 680);
    expect(dashboardCanvas.height, 800);

    final refreshedThemeLayoutField = tester
        .widget<DropdownButtonFormField<ThemeLayout>>(
          find.byType(DropdownButtonFormField<ThemeLayout>),
        );
    refreshedThemeLayoutField.onChanged!(ThemeLayout.stage);
    await tester.pump();
    final stageCanvas = tester.widget<SizedBox>(
      find.byKey(const Key('theme-preview-canvas')),
    );
    expect(stageCanvas.width, 1320);
    expect(stageCanvas.height, 760);
    expect(find.byKey(const Key('theme-preview-stage-layout')), findsOneWidget);
    expect(
      find.byKey(const Key('theme-preview-dashboard-layout')),
      findsNothing,
    );
    final stageColumn = tester.widget<FractionallySizedBox>(
      find.byKey(const Key('theme-preview-stage-content-column')),
    );
    expect(stageColumn.widthFactor, closeTo(.55, .001));
    expect(find.text('我的霓虹'), findsWidgets);
    expect(
      find.byKey(const Key('theme-preview-primary-swatch')),
      findsOneWidget,
    );
    final swatch = tester.widget<DecoratedBox>(
      find.byKey(const Key('theme-preview-primary-swatch')),
    );
    expect((swatch.decoration as BoxDecoration).color, const Color(0xff112233));
    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-save-apply-button')),
    );
    await tester.tap(find.byKey(const Key('theme-studio-save-apply-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
    'advanced gradient switches create visible two-color preview gradients',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(controller, ThemeStudioScreen(controller: controller)),
      );
      await tester.ensureVisible(
        find.byKey(const Key('theme-studio-new-button')),
      );
      await tester.tap(find.byKey(const Key('theme-studio-new-button')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('theme-advanced-gradients-section')),
      );
      await tester.tap(
        find.byKey(const Key('theme-advanced-gradients-section')),
      );
      await tester.pump();

      for (final key in const [
        Key('theme-stage-gradient-enabled'),
        Key('theme-content-gradient-enabled'),
        Key('theme-card-gradient-enabled'),
      ]) {
        var toggle = tester.widget<SwitchListTile>(find.byKey(key));
        if (toggle.value) {
          toggle.onChanged!(false);
          await tester.pump();
          toggle = tester.widget<SwitchListTile>(find.byKey(key));
        }
        expect(toggle.value, isFalse);
        toggle.onChanged!(true);
        await tester.pump();
      }

      final gradients =
          [
            tester.widget<DecoratedBox>(
              find.byKey(const Key('theme-preview-stage-gradient')),
            ),
            tester.widget<DecoratedBox>(
              find.byKey(const Key('theme-preview-content-gradient')),
            ),
            tester.widget<DecoratedBox>(
              find.byKey(const Key('theme-preview-card-gradient')),
            ),
          ].map(
            (box) =>
                (box.decoration as BoxDecoration).gradient! as LinearGradient,
          );
      for (final gradient in gradients) {
        expect(gradient.colors, hasLength(2));
        expect(gradient.colors.first, isNot(gradient.colors.last));
      }
    },
  );

  testWidgets(
    'edits page and dialog backgrounds independently in the live preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(controller, ThemeStudioScreen(controller: controller)),
      );
      await tester.tap(find.byKey(const Key('theme-studio-new-button')));
      await tester.pump();

      expect(find.text('页面背景'), findsOneWidget);
      expect(find.text('对话框背景'), findsOneWidget);
      final contentBefore = _previewGradient(
        tester,
        const Key('theme-preview-content-gradient'),
      ).colors.first;
      final cardBefore = _previewGradient(
        tester,
        const Key('theme-preview-card-gradient'),
      ).colors.first;

      await _setThemeColor(
        tester,
        pickerKey: 'theme-color-picker-theme-color-page-background',
        hexKey: 'theme-color-page-background-hex',
        value: 'FF112233',
      );
      await _setThemeColor(
        tester,
        pickerKey: 'theme-color-picker-theme-color-dialog-background',
        hexKey: 'theme-color-dialog-background-hex',
        value: 'FF445566',
      );

      expect(
        _previewColor(tester, const Key('theme-preview-page-background')),
        const Color(0xff112233),
      );
      expect(
        _previewColor(tester, const Key('theme-preview-dialog-background')),
        const Color(0xff445566),
      );
      expect(
        _previewGradient(
          tester,
          const Key('theme-preview-content-gradient'),
        ).colors.first,
        contentBefore,
      );
      expect(
        _previewGradient(
          tester,
          const Key('theme-preview-card-gradient'),
        ).colors.first,
        cardBefore,
      );

      await tester.tap(find.byKey(const Key('theme-studio-save-apply-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final saved = controller.customThemes.single;
      expect(saved.palette.pageBackground, 0xff112233);
      expect(saved.palette.dialogBackground, 0xff445566);
    },
  );
  testWidgets('preview switches widths without exceptions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );
    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-new-button')),
    );
    await tester.tap(find.byKey(const Key('theme-studio-new-button')));
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-narrow-preview-button')),
    );
    await tester.tap(
      find.byKey(const Key('theme-studio-narrow-preview-button')),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-wide-preview-button')),
    );
    await tester.tap(find.byKey(const Key('theme-studio-wide-preview-button')));
    await tester.pump();
  }, skip: true);

  testWidgets('style presets preserve their previous surface colors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('theme-studio-new-button')));
    await tester.pump();

    const cases = [
      (
        key: Key('theme-preset-focus'),
        page: Color(0xffe2e8f0),
        dialog: Color(0xffffffff),
      ),
      (
        key: Key('theme-preset-glass'),
        page: Color(0xffe0e7ff),
        dialog: Color(0xd9ffffff),
      ),
      (
        key: Key('theme-preset-night'),
        page: Color(0xff18181b),
        dialog: Color(0xff27272a),
      ),
      (
        key: Key('theme-preset-fresh'),
        page: Color(0xffecfdf5),
        dialog: Color(0xffffffff),
      ),
    ];

    for (final preset in cases) {
      tester.widget<OutlinedButton>(find.byKey(preset.key)).onPressed!();
      await tester.pump();

      expect(
        _previewColor(tester, const Key('theme-preview-page-background')),
        preset.page,
      );
      expect(
        _previewGradient(
          tester,
          const Key('theme-preview-content-gradient'),
        ).colors.first,
        preset.page,
      );
      expect(
        _previewColor(tester, const Key('theme-preview-dialog-background')),
        preset.dialog,
      );
      expect(
        _previewGradient(
          tester,
          const Key('theme-preview-card-gradient'),
        ).colors.first,
        preset.dialog,
      );
    }
  });

  testWidgets(
    'quick focus preset updates the draft, preview status, and leaves builtin tokens unchanged',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _controller();
      addTearDown(controller.dispose);
      final builtinTokens = AppThemeTokens.forTheme(AppTheme.miku);
      final builtinPrimary = builtinTokens.primary;
      final builtinStage = builtinTokens.stageGradient.colors.first;
      await tester.pumpWidget(
        _host(controller, ThemeStudioScreen(controller: controller)),
      );

      await tester.tap(find.byKey(const Key('theme-studio-new-button')));
      await tester.pump();
      final preset = tester.widget<OutlinedButton>(
        find.byKey(const Key('theme-preset-focus')),
      );
      preset.onPressed!();
      await tester.pump();

      expect(
        tester
            .widget<DropdownButtonFormField<DashboardLayoutMode>>(
              find.byKey(const Key('theme-dashboard-layout-mode')),
            )
            .initialValue,
        DashboardLayoutMode.focus,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<DashboardDensity>>(
              find.byKey(const Key('theme-dashboard-density')),
            )
            .initialValue,
        DashboardDensity.compact,
      );
      expect(
        find.byKey(const Key('theme-preview-gradient-count-0')),
        findsOneWidget,
      );
      expect(find.text('聚焦数据 · 紧凑 · 0 层渐变'), findsOneWidget);
      await tester.tap(find.byKey(const Key('theme-studio-save-apply-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final saved = controller.customThemes.single;
      expect(saved.dashboardLayoutMode, DashboardLayoutMode.focus);
      expect(saved.dashboardDensity, DashboardDensity.compact);
      expect(saved.stageGradientSecondary, isNull);
      expect(saved.contentGradientSecondary, isNull);
      expect(saved.cardGradientSecondary, isNull);
      expect(AppThemeTokens.forTheme(AppTheme.miku).primary, builtinPrimary);
      expect(
        AppThemeTokens.forTheme(AppTheme.miku).stageGradient.colors.first,
        builtinStage,
      );
    },
  );

  testWidgets('save and apply persists the draft as the active custom theme', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );
    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-new-button')),
    );
    await tester.tap(find.byKey(const Key('theme-studio-new-button')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('theme-name-field')), '保存的主题');

    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-save-apply-button')),
    );
    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-save-apply-button')),
    );
    await tester.tap(find.byKey(const Key('theme-studio-save-apply-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.customThemes.single.name, '保存的主题');
    expect(
      controller.themeReference.customThemeId,
      controller.customThemes.single.id,
    );
  });

  testWidgets(
    'builtin preset cannot be deleted and can be copied into a draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(controller, ThemeStudioScreen(controller: controller)),
      );

      expect(find.byTooltip('删除 MIKU'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('theme-studio-copy-miku-button')),
      );
      await tester.tap(find.byKey(const Key('theme-studio-copy-miku-button')));
      await tester.pump();
      expect(find.text('编辑草稿'), findsOneWidget);
    },
  );

  testWidgets(
    'renaming a custom theme updates its list entry and draft title',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _controller();
      addTearDown(controller.dispose);
      final custom = controller.copyBuiltinTheme(AppTheme.miku);
      await controller.saveCustomTheme(custom);
      await tester.pumpWidget(
        _host(controller, ThemeStudioScreen(controller: controller)),
      );

      await tester.ensureVisible(find.text(custom.name));
      await tester.tap(find.text(custom.name));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(Key('theme-studio-rename-${custom.id}')),
      );
      await tester.tap(find.byKey(Key('theme-studio-rename-${custom.id}')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('theme-rename-field')),
        '重命名主题',
      );
      await tester.tap(find.text('确认重命名'));
      await tester.pump();

      expect(find.text('重命名主题'), findsWidgets);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('theme-name-field')))
            .controller!
            .text,
        '重命名主题',
      );
    },
  );

  testWidgets('restore saved version discards unsaved draft changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    final custom = controller.copyBuiltinTheme(AppTheme.miku);
    await controller.saveCustomTheme(custom);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );

    await tester.ensureVisible(find.text(custom.name));
    await tester.tap(find.text(custom.name));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('theme-name-field')), '未保存名称');
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('theme-studio-restore-saved-button')),
    );
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('theme-name-field')))
          .controller!
          .text,
      custom.name,
    );
  });

  testWidgets('deleting a custom theme requires confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    final custom = controller.copyBuiltinTheme(AppTheme.miku);
    await controller.saveCustomTheme(custom);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );

    await tester.ensureVisible(
      find.byKey(Key('theme-studio-delete-${custom.id}')),
    );
    await tester.tap(find.byKey(Key('theme-studio-delete-${custom.id}')));
    await tester.pump();
    expect(find.text('删除自定义主题？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(controller.customThemes, hasLength(1));

    await tester.ensureVisible(
      find.byKey(Key('theme-studio-delete-${custom.id}')),
    );
    await tester.tap(find.byKey(Key('theme-studio-delete-${custom.id}')));
    await tester.pump();
    await tester.tap(find.text('确认删除'));
    await tester.pump();
    expect(controller.customThemes, isEmpty);
  });

  testWidgets(
    'resetting creates a draft copied from the active builtin theme',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(controller, ThemeStudioScreen(controller: controller)),
      );

      await tester.tap(find.byKey(const Key('theme-studio-new-button')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('theme-studio-reset-builtin-button')),
      );
      await tester.tap(
        find.byKey(const Key('theme-studio-reset-builtin-button')),
      );
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('theme-name-field')))
            .controller!
            .text,
        contains('副本'),
      );
    },
  );

  testWidgets('shows import action without auto-applying themes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        controller,
        ThemeStudioScreen(
          controller: controller,
          themePackagePicker: () async => null,
        ),
      ),
    );

    expect(find.byKey(const Key('theme-studio-import-button')), findsOneWidget);
    expect(
      controller.themeReference,
      const ThemeReference.builtin(AppTheme.miku),
    );
    expect(controller.customThemes, isEmpty);
  });

  testWidgets('exports only custom themes as a readable package', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await Directory.systemTemp.createTemp('theme_studio_export_');
    addTearDown(() => root.delete(recursive: true));
    final controller = await _controller();
    addTearDown(controller.dispose);
    final custom = controller.copyBuiltinTheme(AppTheme.miku);
    await controller.saveCustomTheme(custom);
    final destinationWithoutExtension =
        '${root.path}${Platform.pathSeparator}shared-theme';
    await tester.pumpWidget(
      _host(
        controller,
        ThemeStudioScreen(
          controller: controller,
          themePackageSavePicker: (_) async =>
              FileSaveLocation(destinationWithoutExtension),
          themePackageExportAction: (theme, destination) =>
              ThemePackageService().exportTheme(
                theme,
                destination: destination,
              ),
        ),
      ),
    );

    expect(find.byTooltip('导出 MIKU'), findsNothing);
    expect(find.byKey(Key('theme-studio-export-${custom.id}')), findsOneWidget);
  }, skip: true);

  testWidgets('back with a dirty draft asks whether to save or discard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );
    await tester.ensureVisible(
      find.byKey(const Key('theme-studio-new-button')),
    );
    await tester.tap(find.byKey(const Key('theme-studio-new-button')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('theme-name-field')), '未保存');

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('保存草稿更改？'), findsOneWidget);
    expect(find.text('放弃'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });
  _uiControlsTests();
}

Future<void> _setThemeColor(
  WidgetTester tester, {
  required String pickerKey,
  required String hexKey,
  required String value,
}) async {
  await tester.ensureVisible(find.byKey(Key(pickerKey)));
  await tester.tap(find.byKey(Key(pickerKey)));
  await tester.pump();
  await tester.tap(find.text('高级输入（十六进制）'));
  await tester.pump();
  await tester.enterText(find.byKey(Key(hexKey)), value);
  await tester.pump();
  await tester.tap(find.text('完成'));
  await tester.pump();
}

LinearGradient _previewGradient(WidgetTester tester, Key key) {
  final preview = tester.widget<DecoratedBox>(find.byKey(key));
  return (preview.decoration as BoxDecoration).gradient! as LinearGradient;
}

Color? _previewColor(WidgetTester tester, Key key) {
  final preview = tester.widget<DecoratedBox>(find.byKey(key));
  return (preview.decoration as BoxDecoration).color;
}

void _uiControlsTests() {
  testWidgets('color cards open HSV picker and advanced hex updates preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('theme-studio-new-button')));
    await tester.pump();
    expect(find.byKey(const Key('theme-color-primary')), findsNothing);
    final picker = find.byKey(
      const Key('theme-color-picker-theme-color-primary'),
    );
    expect(picker, findsOneWidget);
    await tester.tap(picker);
    await tester.pump();
    for (final key in const [
      'theme-color-hue-slider',
      'theme-color-saturation-slider',
      'theme-color-value-slider',
      'theme-color-opacity-slider',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    tester
        .widget<Slider>(find.byKey(const Key('theme-color-hue-slider')))
        .onChanged!(.5);
    await tester.pump();
    final swatch = tester.widget<DecoratedBox>(
      find.byKey(const Key('theme-preview-primary-swatch')),
    );
    expect(
      (swatch.decoration as BoxDecoration).color,
      isNot(const Color(0xff39c5bb)),
    );
    await tester.tap(find.text('高级输入（十六进制）'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('theme-color-primary-hex')),
      'FF112233',
    );
    await tester.pump();
    final updated = tester.widget<DecoratedBox>(
      find.byKey(const Key('theme-preview-primary-swatch')),
    );
    expect(
      (updated.decoration as BoxDecoration).color,
      const Color(0xff112233),
    );
  });

  testWidgets('radius and opacity sliders update preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller, ThemeStudioScreen(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('theme-studio-new-button')));
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const Key('theme-card-radius-slider')))
        .onChanged!(37);
    tester
        .widget<Slider>(find.byKey(const Key('theme-shadow-opacity-slider')))
        .onChanged!(.73);
    await tester.pump();
    final content = tester.widget<DecoratedBox>(
      find.byKey(const Key('theme-preview-content-gradient')),
    );
    expect(
      (content.decoration as BoxDecoration).boxShadow!.single.color.a,
      closeTo(.73, .01),
    );
  });
}
