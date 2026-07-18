import 'dart:convert';
import 'dart:io';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/services/theme_background_store.dart';
import 'package:agent_battery_flutter/services/theme_package_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stateKey = 'agent_battery_state_v1';
const _themeId = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';

class _MemoryKeys implements SecureKeyStore {
  @override
  Future<void> delete(String key) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Backgrounds implements ThemeBackgroundService {
  final List<String> deleted = [];
  bool failImport = false;

  @override
  Future<void> delete(String fileName) async => deleted.add(fileName);

  @override
  Future<String> importFile({
    required String themeId,
    required File source,
  }) async {
    if (failImport) throw StateError('background import failed');
    return '$themeId-imported.webp';
  }

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
  apiKey: '',
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
  required ThemePackageService packages,
  _Backgrounds? backgrounds,
  bool failSave = false,
}) async {
  SharedPreferences.setMockInitialValues({
    _stateKey: jsonEncode(snapshot.toJson()),
  });
  final controller = BatteryController(
    storage: _FailingStorage(keyStore: _MemoryKeys(), failSave: failSave),
    api: ApiClient(),
    backgrounds: backgrounds ?? _Backgrounds(),
    themePackages: packages,
  );
  await controller.initialize(refreshOnStart: false);
  return controller;
}

class _FailingStorage extends StorageService {
  _FailingStorage({required super.keyStore, required this.failSave});
  final bool failSave;
  int _saves = 0;

  @override
  Future<void> save(AppSnapshot snapshot) {
    _saves += 1;
    if (failSave && _saves > 1) throw StateError('save failed');
    return super.save(snapshot);
  }
}

void main() {
  late Directory root;
  late ThemePackageService packages;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'theme_package_controller_test_',
    );
    packages = ThemePackageService(temporaryDirectory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'imports with a new ID and leaves providers, usage, and reference unchanged',
    () async {
      final package = await _export(packages, root, _customTheme);
      final controller = await _controller(
        const AppSnapshot(providerConfigs: [_provider]),
        packages: packages,
      );
      addTearDown(controller.dispose);
      final configs = controller.configs;
      final reference = controller.themeReference;

      final imported = await controller.importCustomTheme(package);

      expect(imported.id, isNot(_customTheme.id));
      expect(imported.name, 'Midnight 导入');
      expect(controller.customThemes, [imported]);
      expect(controller.configs, configs);
      expect(controller.themeReference, reference);
    },
  );

  test(
    'imports background through managed store and applies only when requested',
    () async {
      final source = await _write(root, 'source.webp', [1, 2]);
      final package = await _export(
        packages,
        root,
        _customTheme.copyWith(backgroundImageFileName: 'other-machine.webp'),
        background: source,
      );
      final backgrounds = _Backgrounds();
      final controller = await _controller(
        const AppSnapshot(),
        backgrounds: backgrounds,
        packages: packages,
      );
      addTearDown(controller.dispose);

      final imported = await controller.importCustomTheme(package, apply: true);

      expect(imported.backgroundImageFileName, '${imported.id}-imported.webp');
      expect(controller.themeReference, ThemeReference.custom(imported.id));
    },
  );

  test(
    'rolls back imported managed background when theme persistence fails',
    () async {
      final source = await _write(root, 'source.webp', [1, 2]);
      final package = await _export(
        packages,
        root,
        _customTheme.copyWith(backgroundImageFileName: 'other-machine.webp'),
        background: source,
      );
      final backgrounds = _Backgrounds();
      final controller = await _controller(
        const AppSnapshot(),
        backgrounds: backgrounds,
        packages: packages,
        failSave: true,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.importCustomTheme(package),
        throwsStateError,
      );

      expect(controller.customThemes, isEmpty);
      expect(backgrounds.deleted, hasLength(1));
    },
  );
}

Future<File> _export(
  ThemePackageService packages,
  Directory root,
  CustomTheme theme, {
  File? background,
}) async {
  final destination = File(
    '${root.path}${Platform.pathSeparator}'
    '${DateTime.now().microsecondsSinceEpoch}.agentbattery-theme',
  );
  return packages.exportTheme(
    theme,
    destination: destination,
    background: background,
  );
}

Future<File> _write(Directory root, String name, List<int> bytes) async {
  final file = File('${root.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}
