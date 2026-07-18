import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProviderConfig persists API metadata and generic billing only', () {
    final billing = _billingConfig();
    final config = ProviderConfig(
      id: 'custom',
      name: 'Custom API',
      colorValue: 0xff123456,
      order: 3,
      enabled: true,
      baseUrl: 'https://example.com/v1',
      apiKey: 'test-key',
      defaultModel: 'model-x',
      rechargeUrl: 'https://example.com/recharge',
      lowBalanceThreshold: 12.5,
      webBillingConfig: billing,
    );

    final json = config.toJson(includeApiKey: true);
    final restored = ProviderConfig.fromJson(json);
    const retiredKeys = [
      'advanced_enabled',
      'balance_request',
      'daily_request',
      'monthly_request',
      'daily_usage_fallback',
      'monthly_usage_fallback',
      'balance_url',
      'balance_method',
      'balance_body',
      'balance_headers',
      'balance_json_path',
      'daily_usage_json_path',
      'monthly_usage_json_path',
      'balance_token',
      'bill_cookie',
      'wallet_cookie',
      'wallet_subject_id',
    ];

    expect(restored.apiKey, 'test-key');
    expect(restored.defaultModel, 'model-x');
    expect(restored.rechargeUrl, 'https://example.com/recharge');
    expect(restored.lowBalanceThreshold, 12.5);
    expect(restored.webBillingConfig?.toJson(), billing.toJson());
    expect(restored.maskedApiKey, 'te••••ey');
    for (final key in retiredKeys) {
      expect(json, isNot(containsPair(key, anything)));
    }
  });

  test('ProviderConfig accepts a provider without web billing configuration', () {
    final config = ProviderConfig.fromJson({
      'id': 'metadata-only',
      'name': 'Metadata only',
      'color': 1,
      'order': 0,
      'enabled': true,
      'base_url': 'https://example.test/',
    });

    expect(config.webBillingConfig, isNull);
    expect(config.normalizedBaseUrl, 'https://example.test/v1');
    expect(config.toJson(), isNot(contains('web_billing_config')));
  });

  test('AppSnapshot keeps supported themes independent of billing architecture', () {
    for (final theme in AppTheme.values) {
      final restored = AppSnapshot.fromJson(
        AppSnapshot(theme: theme).toJson(),
      );
      expect(restored.theme, theme);
    }

    expect(AppSnapshot.fromJson({'theme': 'mita'}).theme, AppTheme.mita);
    expect(AppSnapshot.fromJson({'theme': 'other'}).theme, AppTheme.glass);
    expect(AppSnapshot.fromJson({'theme': 'unknown'}).theme, AppTheme.miku);
  });
}

WebBillingConfig _billingConfig() => WebBillingConfig(
  schemaVersion: 1,
  source: 'generic',
  secretVariableDefinitions: [
    SecretVariableDefinition(
      id: 'token',
      name: 'TOKEN',
      displayName: 'Token',
      type: SecretVariableType.bearerToken,
      required: true,
    ),
  ],
  requestTemplates: [
    RequestTemplate(
      id: 'balance',
      method: 'GET',
      urlTemplate: 'https://billing.example.test/balance',
      headersTemplate: {'Authorization': r'Bearer ${TOKEN}'},
    ),
  ],
  metricRules: [
    MetricRule(
      id: 'balance',
      kind: WebBillingMetricKind.balance,
      requestTemplateId: 'balance',
      responseRule: ResponseRule(scalarPath: 'balance'),
    ),
  ],
);
