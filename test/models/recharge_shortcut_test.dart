import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recharge shortcut fields persist without exposing secrets', () {
    const config = ProviderConfig(
      id: 'custom',
      name: 'Custom API',
      colorValue: 0xff123456,
      order: 3,
      enabled: true,
      baseUrl: 'https://example.com/v1',
      apiKey: 'test-key',
      rechargeUrl: 'https://example.com/billing',
      lowBalanceThreshold: 12.5,
    );

    final json = config.toJson();
    final restored = ProviderConfig.fromJson(json);

    expect(restored.rechargeUrl, 'https://example.com/billing');
    expect(restored.lowBalanceThreshold, 12.5);
    expect(json.containsKey('api_key'), isFalse);
  });

  test('old provider configuration defaults recharge shortcut fields', () {
    final config = ProviderConfig.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'color': 0xff123456,
      'order': 0,
      'enabled': true,
      'base_url': 'https://example.com/v1',
    });

    expect(config.rechargeUrl, isEmpty);
    expect(config.lowBalanceThreshold, isNull);
  });

  test('only absolute http and https recharge URLs are valid', () {
    expect(isValidRechargeUrl('https://example.com/billing'), isTrue);
    expect(isValidRechargeUrl('http://example.com/billing'), isTrue);
    expect(isValidRechargeUrl('example.com/billing'), isFalse);
    expect(isValidRechargeUrl('ftp://example.com/billing'), isFalse);
    expect(isValidRechargeUrl('https://'), isFalse);
  });

  test('unsafe persisted low balance thresholds are disabled', () {
    for (final value in [
      'NaN',
      'Infinity',
      '-1',
      double.nan,
      double.infinity,
    ]) {
      final config = ProviderConfig.fromJson({
        'id': 'custom',
        'name': 'Custom',
        'color': 0xff123456,
        'order': 0,
        'enabled': true,
        'base_url': 'https://example.com/v1',
        'low_balance_threshold': value,
      });
      expect(config.lowBalanceThreshold, isNull);
    }
  });
}
