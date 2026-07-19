import 'dart:convert';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/hermes_provider_importer.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

String _persistedSnapshot(ProviderConfig config) => jsonEncode({
  'provider_configs': [config.toJson()],
});

WebBillingConfig _genericBillingConfig({String source = 'generic'}) =>
    WebBillingConfig(
      schemaVersion: 1,
      source: source,
      secretVariableDefinitions: const [
        SecretVariableDefinition(
          id: 'token',
          name: 'TOKEN',
          displayName: 'Token',
          type: SecretVariableType.bearerToken,
          required: true,
        ),
      ],
      requestTemplates: const [
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
          responseRule: ResponseRule(scalarPath: 'data.balance'),
        ),
      ],
    );

const _themeId = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';

CustomTheme _customTheme() => CustomTheme(
  id: _themeId,
  name: 'Storage Theme',
  layout: ThemeLayout.stage,
  palette: const ThemePalette(
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
  ),
  cardRadius: 24,
  controlRadius: 16,
  contentRadius: 34,
  shadowOpacity: .45,
  stageOverlayOpacity: .28,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'load persists a generic billing config and removes JSON API keys',
    () async {
      const apiKey = 'legacy-api-key';
      final billing = _genericBillingConfig();
      final config = ProviderConfig(
        id: 'custom',
        name: 'Custom',
        colorValue: 1,
        order: 0,
        enabled: true,
        baseUrl: 'https://custom.example/v1',
        apiKey: apiKey,
        webBillingConfig: billing,
      );
      SharedPreferences.setMockInitialValues({
        'agent_battery_state_v1': jsonEncode({
          'provider_configs': [
            {...config.toJson(), 'api_key': apiKey},
          ],
        }),
      });
      final keys = InMemorySecureKeyStore();
      final loaded = await StorageService(keyStore: keys).load();
      final persisted =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'agent_battery_state_v1',
                )!,
              )
              as Map<String, dynamic>;
      final saved = (persisted['provider_configs'] as List).single as Map;

      expect(loaded.providerConfigs.single.apiKey, apiKey);
      expect(
        loaded.providerConfigs.single.webBillingConfig?.toJson(),
        billing.toJson(),
      );
      expect(saved['web_billing_config'], billing.toJson());
      expect(jsonEncode(saved), isNot(contains(apiKey)));
      for (final key in [
        'advanced_enabled',
        'daily_request',
        'balance_request',
        'monthly_request',
        'balance_url',
        'balance_token',
        'bill_cookie',
        'wallet_cookie',
        'wallet_subject_id',
      ]) {
        expect(saved, isNot(containsPair(key, anything)));
      }
    },
  );

  test(
    'load leaves a metadata-only provider without billing configuration',
    () async {
      const config = ProviderConfig(
        id: 'custom',
        name: 'Custom',
        colorValue: 1,
        order: 0,
        enabled: true,
        baseUrl: 'https://custom.example/v1',
      );
      SharedPreferences.setMockInitialValues({
        'agent_battery_state_v1': _persistedSnapshot(config),
      });

      final loaded = await StorageService(
        keyStore: InMemorySecureKeyStore(),
      ).load();

      expect(loaded.providerConfigs.single.webBillingConfig, isNull);
    },
  );

  test(
    'load-save migrates old billing while retaining v3 theme and recharge data',
    () async {
      final theme = _customTheme();
      final rawProvider = <String, Object?>{
        'id': 'deepseek',
        'name': 'DeepSeek',
        'color': 0xff365edc,
        'order': 0,
        'enabled': true,
        'base_url': 'https://api.deepseek.com/v1',
        'recharge_url': 'https://platform.deepseek.com/top_up',
        'low_balance_threshold': 9.5,
        'advanced_enabled': true,
        'balance_url': 'https://api.deepseek.com/user/balance',
        'balance_json_path': 'balance_infos[0].total_balance',
        'daily_request': deepSeekDailyCostRequest.toJson(),
        'monthly_request': deepSeekMonthlyCostRequest.toJson(),
      };
      SharedPreferences.setMockInitialValues({
        'agent_battery_state_v1': jsonEncode({
          'version': 3,
          'provider_configs': [rawProvider],
          'theme_reference': const ThemeReference.custom(_themeId).toJson(),
          'custom_themes': [theme.toJson()],
          'auto_refresh_enabled': true,
          'auto_refresh_interval_seconds': 90,
        }),
      });

      final loaded = await StorageService(
        keyStore: InMemorySecureKeyStore(),
      ).load();
      final saved =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'agent_battery_state_v1',
                )!,
              )
              as Map<String, dynamic>;
      final savedProvider = (saved['provider_configs'] as List).single as Map;

      expect(saved['version'], 3);
      expect(loaded.themeReference, const ThemeReference.custom(_themeId));
      expect(loaded.customThemes, [theme]);
      expect(loaded.autoRefreshIntervalSeconds, 90);
      expect(
        loaded.providerConfigs.single.rechargeUrl,
        rawProvider['recharge_url'],
      );
      expect(
        loaded.providerConfigs.single.lowBalanceThreshold,
        rawProvider['low_balance_threshold'],
      );
      expect(
        loaded.providerConfigs.single.webBillingConfig?.source,
        'legacy_deepseek',
      );
      expect(savedProvider['recharge_url'], rawProvider['recharge_url']);
      expect(
        savedProvider['low_balance_threshold'],
        rawProvider['low_balance_threshold'],
      );
      expect(savedProvider['web_billing_config'], isNotNull);
      for (final key in [
        'advanced_enabled',
        'balance_url',
        'balance_json_path',
        'daily_request',
        'monthly_request',
      ]) {
        expect(savedProvider, isNot(containsPair(key, anything)));
      }
    },
  );

  test('existing web billing config wins over legacy billing JSON', () async {
    final existingBilling = _genericBillingConfig(source: 'current');
    SharedPreferences.setMockInitialValues({
      'agent_battery_state_v1': jsonEncode({
        'version': 3,
        'provider_configs': [
          {
            'id': 'deepseek',
            'name': 'DeepSeek',
            'color': 0xff365edc,
            'order': 0,
            'enabled': true,
            'base_url': 'https://api.deepseek.com/v1',
            'web_billing_config': existingBilling.toJson(),
            'advanced_enabled': true,
            'balance_url': 'https://api.deepseek.com/user/balance',
            'balance_json_path': 'balance_infos[0].total_balance',
            'daily_request': deepSeekDailyCostRequest.toJson(),
            'monthly_request': deepSeekMonthlyCostRequest.toJson(),
          },
        ],
      }),
    });

    final loaded = await StorageService(
      keyStore: InMemorySecureKeyStore(),
    ).load();

    expect(
      loaded.providerConfigs.single.webBillingConfig?.toJson(),
      existingBilling.toJson(),
    );
  });

  test(
    'deleteProviderSecrets cleans declared values and preserves other scopes and themes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = InMemorySecureKeyStore();
      for (final key in [
        ProviderKeyManager.keyFor('provider-a'),
        ProviderKeyManager.balanceTokenKeyFor('provider-a'),
        ProviderKeyManager.billCookieKeyFor('provider-a'),
        ProviderKeyManager.walletCookieKeyFor('provider-a'),
        ProviderKeyManager.walletSubjectIdKeyFor('provider-a'),
        ProviderKeyManager.webBillingVariableKeyFor('provider-a', 'token'),
        ProviderKeyManager.keyFor('provider-b'),
        ProviderKeyManager.webBillingVariableKeyFor('provider-b', 'token'),
      ]) {
        keys.values[key] = 'stored-value';
      }
      final storage = StorageService(keyStore: keys);
      final snapshot = AppSnapshot(
        themeReference: const ThemeReference.custom(_themeId),
        customThemes: [_customTheme()],
      );
      await storage.save(snapshot);

      await storage.deleteProviderSecrets('provider-a', const ['token']);

      expect(keys.values[ProviderKeyManager.keyFor('provider-a')], isNull);
      expect(
        keys.values[ProviderKeyManager.balanceTokenKeyFor('provider-a')],
        isNull,
      );
      expect(
        keys.values[ProviderKeyManager.webBillingVariableKeyFor(
          'provider-a',
          'token',
        )],
        isNull,
      );
      expect(
        keys.values[ProviderKeyManager.keyFor('provider-b')],
        'stored-value',
      );
      expect(
        keys.values[ProviderKeyManager.webBillingVariableKeyFor(
          'provider-b',
          'token',
        )],
        'stored-value',
      );
      final persisted = AppSnapshot.fromJson(
        Map<String, Object?>.from(
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'agent_battery_state_v1',
                )!,
              )
              as Map,
        ),
      );
      expect(persisted.themeReference, const ThemeReference.custom(_themeId));
      expect(persisted.customThemes, [_customTheme()]);
    },
  );

  test(
    'Hermes import saves API keys securely while preserving billing state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = InMemorySecureKeyStore()
        ..values[ProviderKeyManager.webBillingVariableKeyFor(
              'provider-a',
              'token',
            )] =
            'local-generic-token';
      final storage = StorageService(keyStore: keys);
      final billing = _genericBillingConfig(source: 'local');
      final existing = ProviderConfig(
        id: 'provider-a',
        name: 'Existing',
        colorValue: 0xff123456,
        order: 7,
        enabled: true,
        baseUrl: 'https://old.example/v1',
        defaultModel: 'old-model',
        rechargeUrl: 'https://old.example/recharge',
        lowBalanceThreshold: 12.5,
        webBillingConfig: billing,
      );
      const replacement = HermesImportedProvider(
        config: ProviderConfig(
          id: 'provider-a',
          name: 'Imported',
          colorValue: 0xffabcdef,
          order: 2,
          enabled: false,
          baseUrl: 'https://new.example/v1',
          defaultModel: 'new-model',
        ),
        apiKey: 'imported-api-key',
      );

      final result = await storage.importHermesProviders(
        AppSnapshot(
          providerConfigs: [existing],
          themeReference: const ThemeReference.custom(_themeId),
          customThemes: [_customTheme()],
        ),
        const [replacement],
      );
      final merged = result.providerConfigs.single;
      final persisted =
          (jsonDecode(
                    (await SharedPreferences.getInstance()).getString(
                      'agent_battery_state_v1',
                    )!,
                  )
                  as Map<String, dynamic>)['provider_configs']
              as List;

      expect(merged.name, 'Imported');
      expect(merged.baseUrl, 'https://new.example/v1');
      expect(merged.defaultModel, 'new-model');
      expect(merged.apiKey, 'imported-api-key');
      expect(
        keys.values[ProviderKeyManager.keyFor('provider-a')],
        'imported-api-key',
      );
      expect(merged.order, 7);
      expect(merged.enabled, isTrue);
      expect(merged.rechargeUrl, 'https://old.example/recharge');
      expect(merged.lowBalanceThreshold, 12.5);
      expect(result.themeReference, const ThemeReference.custom(_themeId));
      expect(result.customThemes, [_customTheme()]);
      expect(merged.webBillingConfig?.toJson(), billing.toJson());
      expect(
        keys.values[ProviderKeyManager.webBillingVariableKeyFor(
          'provider-a',
          'token',
        )],
        'local-generic-token',
      );
      expect(jsonEncode(persisted), isNot(contains('imported-api-key')));
    },
  );

  test(
    'Hermes import with an empty API key preserves the stored key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = InMemorySecureKeyStore()
        ..values[ProviderKeyManager.keyFor('metadata-only')] =
            'existing-api-key';
      final storage = StorageService(keyStore: keys);
      const imported = HermesImportedProvider(
        config: ProviderConfig(
          id: 'metadata-only',
          name: 'Metadata Only',
          colorValue: 1,
          order: 0,
          enabled: false,
          baseUrl: 'https://metadata.example/v1',
          defaultModel: 'model-a',
        ),
      );

      final result = await storage.importHermesProviders(
        const AppSnapshot(),
        const [imported],
      );

      expect(result.providerConfigs, hasLength(1));
      expect(result.providerConfigs.single.name, 'Metadata Only');
      expect(result.providerConfigs.single.apiKey, isEmpty);
      expect(result.providerConfigs.single.webBillingConfig, isNull);
      expect(
        keys.values[ProviderKeyManager.keyFor('metadata-only')],
        'existing-api-key',
      );
    },
  );

  test(
    'Hermes import saves a new inferred DeepSeek skeleton API key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final keys = InMemorySecureKeyStore();
      final storage = StorageService(keyStore: keys);
      const deepSeek = HermesImportedProvider(
        config: ProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          colorValue: 0xff365edc,
          order: 0,
          enabled: false,
          baseUrl: 'https://api.deepseek.com/v1',
          defaultModel: 'deepseek-chat',
        ),
        apiKey: 'deepseek-imported-api-key',
      );

      final result = await storage.importHermesProviders(
        const AppSnapshot(),
        const [deepSeek],
      );
      final persisted =
          (jsonDecode(
                    (await SharedPreferences.getInstance()).getString(
                      'agent_battery_state_v1',
                    )!,
                  )
                  as Map<String, dynamic>)['provider_configs']
              as List;

      expect(result.providerConfigs, hasLength(1));
      expect(result.providerConfigs.single.id, 'deepseek');
      expect(result.providerConfigs.single.apiKey, 'deepseek-imported-api-key');
      expect(result.providerConfigs.single.webBillingConfig, isNull);
      expect(
        keys.values[ProviderKeyManager.keyFor('deepseek')],
        'deepseek-imported-api-key',
      );
      expect(
        jsonEncode(persisted),
        isNot(contains('deepseek-imported-api-key')),
      );
    },
  );
}
