import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ProviderConfig round trips advanced configuration without exposing key',
    () {
      const config = ProviderConfig(
        id: 'custom',
        name: 'Custom API',
        colorValue: 0xff123456,
        order: 3,
        enabled: true,
        baseUrl: 'https://example.com/v1',
        apiKey: 'test-key',
        defaultModel: 'model-x',
        advancedEnabled: true,
        balanceUrl: '/billing',
        balanceMethod: BalanceRequestMethod.post,
        balanceBody: '{"scope":"all"}',
        balanceHeaders: '{"X-Tenant":"demo"}',
        balanceJsonPath: 'data.items[0].amount',
        dailyUsageJsonPath: 'data.daily',
        monthlyUsageJsonPath: 'data.monthly',
      );

      final restored = ProviderConfig.fromJson(
        config.toJson(includeApiKey: true),
      );
      expect(restored, config);
      expect(restored.maskedApiKey, 'te••••ey');
      expect(config.toJson().containsKey('api_key'), isFalse);
    },
  );

  test(
    'AppSnapshot migrates old usage cache into builtin dynamic templates',
    () {
      final snapshot = AppSnapshot.fromJson({
        'providers': {
          'deepseek': {'last_balance': 8.5},
          'kimi': {'last_balance': 4.2},
        },
        'theme': 'miku',
      });

      expect(snapshot.providerConfigs.map((item) => item.id), [
        'deepseek',
        'kimi',
        'pucoding',
      ]);
      expect(snapshot.providers['deepseek']!.lastBalance, 8.5);
      expect(
        snapshot.providerConfigs.first.balanceJsonPath,
        'balance_infos[0].total_balance',
      );
      final pucoding = snapshot.providerConfigs.last;
      expect(pucoding.balanceUrl, 'https://pucoding.com/api/v1/user/account');
      expect(pucoding.balanceJsonPath, 'data.balance');
    },
  );

  test('AppSnapshot restores the persisted Nailong theme', () {
    final snapshot = AppSnapshot.fromJson({
      'theme': 'nailong',
      'provider_configs': const [],
    });

    expect(snapshot.theme, AppTheme.nailong);
    expect(snapshot.themeReference, ThemeReference.builtin(AppTheme.nailong));
  });

  test('accepts only absolute HTTP(S) base URLs', () {
    expect(isValidBaseUrl(' https://api.example.com/v1/ '), isTrue);
    expect(isValidBaseUrl('http://localhost:8080'), isTrue);

    for (final value in [
      '',
      'api.example.com/v1',
      'ftp://api.example.com',
      'https://',
      'not a url',
    ]) {
      expect(isValidBaseUrl(value), isFalse);
    }
  });

  test(
    'AppSnapshot persists each supported theme and migrates other to glass',
    () {
      for (final theme in AppTheme.values) {
        final restored = AppSnapshot.fromJson(
          AppSnapshot(theme: theme).toJson(),
        );
        expect(restored.theme, theme);
      }

      expect(AppSnapshot.fromJson({'theme': 'mita'}).theme, AppTheme.mita);
      expect(AppSnapshot(theme: AppTheme.mita).toJson()['theme'], 'mita');
      expect(AppSnapshot.fromJson({'theme': 'other'}).theme, AppTheme.glass);
      expect(AppSnapshot.fromJson({'theme': 'unknown'}).theme, AppTheme.miku);
    },
  );
}
