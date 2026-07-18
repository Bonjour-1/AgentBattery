import 'dart:convert';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/provider_usage.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stateKey = 'agent_battery_state_v1';

const _providerOne = ProviderConfig(
  id: 'one',
  name: 'One',
  colorValue: 0,
  order: 0,
  enabled: true,
  baseUrl: 'https://one.example/v1',
);

const _providerTwo = ProviderConfig(
  id: 'two',
  name: 'Two',
  colorValue: 0,
  order: 1,
  enabled: true,
  baseUrl: 'https://two.example/v1',
);

const _providerThree = ProviderConfig(
  id: 'three',
  name: 'Three',
  colorValue: 0,
  order: 2,
  enabled: true,
  baseUrl: 'https://three.example/v1',
);

Future<BatteryController> _controllerWithSnapshot(AppSnapshot snapshot) async {
  SharedPreferences.setMockInitialValues({
    _stateKey: jsonEncode(snapshot.toJson()),
  });
  final controller = BatteryController(
    storage: StorageService(),
    api: ApiClient(),
  );
  await controller.initialize();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return controller;
}

void main() {
  test(
    'manually sets one provider daily usage, updates totals, and persists',
    () async {
      final controller = await _controllerWithSnapshot(
        const AppSnapshot(
          providerConfigs: [_providerOne, _providerTwo],
          providers: {
            'one': ProviderUsage(
              date: '2026-07-13',
              month: '2026-07',
              lastBalance: 10,
              dailyUsage: 1.2,
              monthlyUsage: 3.4,
            ),
            'two': ProviderUsage(dailyUsage: 2, monthlyUsage: 5),
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.setManualUsage(
        providerId: 'one',
        period: UsagePeriod.daily,
        amount: 6.789,
      );

      expect(controller.providers['one']!.dailyUsage, 6.79);
      expect(controller.providers['one']!.monthlyUsage, 3.4);
      expect(controller.providers['one']!.balance, 10);
      expect(controller.totalDaily, 8.79);
      expect(controller.totalMonthly, 8.4);

      final persisted =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(_stateKey)!,
              )
              as Map<String, dynamic>;
      expect(persisted['providers']['one']['daily_cumulative'], 6.79);
    },
  );

  test(
    'manually sets one provider monthly usage without changing daily total',
    () async {
      final controller = await _controllerWithSnapshot(
        const AppSnapshot(
          providerConfigs: [_providerOne, _providerTwo],
          providers: {
            'one': ProviderUsage(dailyUsage: 1.2, monthlyUsage: 3.4),
            'two': ProviderUsage(dailyUsage: 2, monthlyUsage: 5),
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.setManualUsage(
        providerId: 'one',
        period: UsagePeriod.monthly,
        amount: 9.876,
      );

      expect(controller.providers['one']!.dailyUsage, 1.2);
      expect(controller.providers['one']!.monthlyUsage, 9.88);
      expect(controller.totalDaily, 3.2);
      expect(controller.totalMonthly, 14.88);
    },
  );

  test(
    'migrates PuCoding away from remote usage overrides to balance-delta accounting',
    () async {
      const storedPuCoding = ProviderConfig(
        id: 'pucoding',
        name: 'PuCoding',
        colorValue: 0,
        order: 0,
        enabled: true,
        baseUrl: 'https://pucoding.com/v1',
        advancedEnabled: true,
        balanceUrl: 'https://pucoding.com/api/v1/user/account',
        balanceJsonPath: 'data.balance',
        dailyUsageJsonPath: 'data.daily_used',
        monthlyUsageJsonPath: 'data.monthly_used',
      );
      final controller = await _controllerWithSnapshot(
        const AppSnapshot(providerConfigs: [storedPuCoding]),
      );
      addTearDown(controller.dispose);

      final config = controller.configs.single;
      expect(config.dailyUsageJsonPath, isEmpty);
      expect(config.monthlyUsageJsonPath, isEmpty);
    },
  );

  test('does not create usage for an unknown provider', () async {
    final controller = await _controllerWithSnapshot(
      const AppSnapshot(providerConfigs: [_providerOne]),
    );
    addTearDown(controller.dispose);

    await controller.setManualUsage(
      providerId: 'missing',
      period: UsagePeriod.daily,
      amount: 1,
    );

    expect(controller.providers.containsKey('missing'), isFalse);
  });

  test('editing an existing provider preserves its list position', () async {
    final controller = await _controllerWithSnapshot(
      const AppSnapshot(
        providerConfigs: [_providerOne, _providerTwo, _providerThree],
      ),
    );
    addTearDown(controller.dispose);

    await controller.saveProvider(_providerTwo.copyWith(name: 'Two Edited'));

    expect(controller.configs.map((config) => config.id), [
      'one',
      'two',
      'three',
    ]);
    expect(controller.configs[1].name, 'Two Edited');
    expect(controller.configs[1].order, 1);
  });

  test('records later balance decreases on top of a manual daily override', () {
    const usage = ProviderUsage(
      date: '2026-07-13',
      month: '2026-07',
      lastBalance: 10,
      dailyUsage: 1,
      monthlyUsage: 3,
    );

    final updated = usage
        .withDailyUsage(6.79)
        .recordBalance(8.75, DateTime(2026, 7, 13));

    expect(updated.dailyUsage, 8.04);
    expect(updated.monthlyUsage, 4.25);
    expect(updated.lastBalance, 8.75);
  });
}
