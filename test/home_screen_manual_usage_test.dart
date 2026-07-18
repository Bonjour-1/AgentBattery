import 'dart:convert';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/provider_usage.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:agent_battery_flutter/ui/screens/home_screen.dart';
import 'package:agent_battery_flutter/ui/theme/app_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stateKey = 'agent_battery_state_v1';

class _MemorySecureKeyStore implements SecureKeyStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

const _provider = ProviderConfig(
  id: 'test',
  name: '测试供应商',
  colorValue: 0xff39c5bb,
  order: 0,
  enabled: true,
  baseUrl: 'https://example.com/v1',
);

Future<BatteryController> _controller() async {
  SharedPreferences.setMockInitialValues({
    _stateKey: jsonEncode(
      const AppSnapshot(
        theme: AppTheme.cute,
        providerConfigs: [_provider],
        providers: {
          'test': ProviderUsage(
            lastBalance: 10,
            dailyUsage: 1.2,
            monthlyUsage: 3.4,
          ),
        },
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

Widget _host(BatteryController controller) => MaterialApp(
  theme: AppThemeTokens.forTheme(AppTheme.cute).materialTheme(),
  home: AnimatedBuilder(
    animation: controller,
    builder: (_, _) => HomeScreen(controller: controller),
  ),
);

void main() {
  testWidgets('edits daily usage from its own dialog and updates the display', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    await tester.tap(find.byTooltip('修改今日用量'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('修改 测试供应商 今日用量'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('1.20'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '6.789');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('修改 测试供应商 今日用量'), findsNothing);
    expect(controller.providers['test']!.dailyUsage, 6.79);
    expect(find.text('¥ 6.79'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits monthly usage from its own dialog', (tester) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    await tester.tap(find.byTooltip('修改本月用量'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('修改 测试供应商 本月用量'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '9.876');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.providers['test']!.monthlyUsage, 9.88);
    expect(find.text('¥ 9.88'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the dialog open and reports invalid manual usage', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    await tester.tap(find.byTooltip('修改今日用量'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), '-1');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('修改 测试供应商 今日用量'), findsOneWidget);
    expect(find.text('请输入有限且不小于 0 的金额'), findsOneWidget);
    expect(controller.providers['test']!.dailyUsage, 1.2);
  });
}
