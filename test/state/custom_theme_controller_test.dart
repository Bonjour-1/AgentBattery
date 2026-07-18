import 'dart:convert';
import 'dart:io';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/provider_usage.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/services/theme_background_store.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stateKey = 'agent_battery_state_v1';
const _themeId = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeThemeBackgroundStore implements ThemeBackgroundService {
  final List<String> deleted = [];
  String importedFileName = 'new-background.webp';
  bool failDelete = false;

  @override
  Future<void> delete(String fileName) async {
    if (failDelete) throw StateError('background deletion failed');
    deleted.add(fileName);
  }

  @override
  Future<String> importFile({required String themeId, required File source}) async =>
      importedFileName;

  @override
  Future<File?> resolve(String fileName) async => null;
}

const _provider = ProviderConfig(
  id: 'one',
  name: 'One',
  colorValue: 0xff123456,
  order: 0,
  enabled: true,
  baseUrl: 'https://one.example/v1',
  apiKey: 'provider-key',
);

final _customTheme = CustomTheme(
  id: _themeId,
  name: 'Midnight',
  layout: ThemeLayout.stage,
  palette: const ThemePalette(
    primary: 0xff15968e,
    secondary: 0xffff8fab,
    stage: 0xff0d5753,
    content: 0xffe9fffd,
    card: 0xfff3fffe,
    cardAlt: 0xffddf8f5,
    text: 0xff123f3d,
    mutedText: 0xff557a77,
    onStage: 0xffffffff,
    outline: 0xffb6e4df,
    success: 0xff13867f,
    error: 0xffc34c70,
    statusIdle: 0xff687b79,
    shadow: 0xff0d5c57,
  ),
  cardRadius: 24,
  controlRadius: 16,
  contentRadius: 34,
  shadowOpacity: .4,
  stageOverlayOpacity: .3,
);

Future<BatteryController> _controller(
  AppSnapshot snapshot, {
  _FakeThemeBackgroundStore? backgrounds,
}) async {
  SharedPreferences.setMockInitialValues({_stateKey: jsonEncode(snapshot.toJson())});
  final controller = BatteryController(
    storage: StorageService(keyStore: _MemorySecureKeyStore()),
    api: ApiClient(),
    backgrounds: backgrounds ?? _FakeThemeBackgroundStore(),
  );
  await controller.initialize(refreshOnStart: false);
  return controller;
}

void main() {
  test('copies a builtin preset into an independently editable UUID draft', () async {
    final controller = await _controller(const AppSnapshot());
    addTearDown(controller.dispose);

    final draft = controller.copyBuiltinTheme(AppTheme.miku);

    expect(draft.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(draft.name, 'MIKU 副本');
    expect(draft.layout, ThemeLayout.stage);
    expect(draft.palette.primary, 0xff15968e);
    expect(draft.cardRadius, 24);
    expect(controller.customThemes, isEmpty);
  });

  test('saves and applies a custom theme without changing providers or usage', () async {
    final controller = await _controller(
      AppSnapshot(
        providerConfigs: const [_provider],
        providers: const {'one': ProviderUsage(lastBalance: 9, dailyUsage: 2)},
      ),
    );
    addTearDown(controller.dispose);
    final configs = controller.configs;
    final usage = controller.providers['one'];

    await controller.saveCustomTheme(_customTheme);
    await controller.applyThemeReference(ThemeReference.custom(_themeId));

    expect(controller.customThemes, [_customTheme]);
    expect(controller.themeReference, const ThemeReference.custom(_themeId));
    expect(controller.resolvedTheme.name, 'Midnight');
    expect(controller.configs, configs);
    expect(controller.providers['one'], usage);
  });

  test('renames custom themes but never builtin presets', () async {
    final controller = await _controller(AppSnapshot(customThemes: [_customTheme]));
    addTearDown(controller.dispose);

    await controller.renameCustomTheme(_themeId, ' Renamed ');
    await controller.renameCustomTheme('miku', 'Not allowed');

    expect(controller.customThemes.single.name, 'Renamed');
    expect(controller.themeReference, const ThemeReference.builtin(AppTheme.miku));
  });

  test('deleting protected or missing themes does not alter custom records', () async {
    final controller = await _controller(AppSnapshot(customThemes: [_customTheme]));
    addTearDown(controller.dispose);

    await controller.deleteCustomTheme('miku');
    await controller.deleteCustomTheme('missing');

    expect(controller.customThemes, [_customTheme]);
  });

  test('deleting the active custom theme cleans its background then falls back', () async {
    final backgrounds = _FakeThemeBackgroundStore();
    final themed = _customTheme.copyWith(backgroundImageFileName: 'old.webp');
    final controller = await _controller(
      AppSnapshot(
        themeReference: const ThemeReference.custom(_themeId),
        customThemes: [themed],
      ),
      backgrounds: backgrounds,
    );
    addTearDown(controller.dispose);

    await controller.deleteCustomTheme(_themeId);

    expect(backgrounds.deleted, ['old.webp']);
    expect(controller.customThemes, isEmpty);
    expect(controller.themeReference, const ThemeReference.builtin(AppTheme.miku));
  });

  test('background cleanup failure leaves the theme record and active reference intact', () async {
    final backgrounds = _FakeThemeBackgroundStore()..failDelete = true;
    final themed = _customTheme.copyWith(backgroundImageFileName: 'old.webp');
    final controller = await _controller(
      AppSnapshot(
        themeReference: const ThemeReference.custom(_themeId),
        customThemes: [themed],
      ),
      backgrounds: backgrounds,
    );
    addTearDown(controller.dispose);

    await expectLater(controller.deleteCustomTheme(_themeId), throwsStateError);

    expect(controller.customThemes, [themed]);
    expect(controller.themeReference, const ThemeReference.custom(_themeId));
  });

  test('imports a background by saving new theme state before deleting old file', () async {
    final backgrounds = _FakeThemeBackgroundStore();
    final old = _customTheme.copyWith(backgroundImageFileName: 'old.webp');
    final controller = await _controller(AppSnapshot(customThemes: [old]), backgrounds: backgrounds);
    addTearDown(controller.dispose);

    await controller.importCustomThemeBackground(_themeId, File('source.webp'));

    expect(controller.customThemes.single.backgroundImageFileName, 'new-background.webp');
    expect(backgrounds.deleted, ['old.webp']);
  });

  test('unknown reference applies the safe MIKU fallback', () async {
    final controller = await _controller(const AppSnapshot());
    addTearDown(controller.dispose);

    await controller.applyThemeReference(const ThemeReference.custom(_themeId));

    expect(controller.themeReference, const ThemeReference.builtin(AppTheme.miku));
  });
}
