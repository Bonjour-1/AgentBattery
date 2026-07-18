import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/services/web_billing_migrations.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};
  bool failWrites = false;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('secure storage unavailable');
    values[key] = value;
  }
}

ProviderConfig config({
  String id = 'provider-a',
  String apiKey = '',
  WebBillingConfig? webBillingConfig,
}) => ProviderConfig(
  id: id,
  name: 'Provider A',
  colorValue: 0xff123456,
  order: 0,
  enabled: true,
  baseUrl: 'https://example.invalid/v1',
  apiKey: apiKey,
  webBillingConfig: webBillingConfig,
);

void main() {
  group('ProviderKeyManager', () {
    test(
      'stores generic web billing candidates only in their scoped secure keys',
      () async {
        final store = InMemorySecureKeyStore();
        final storage = StorageService(keyStore: store);
        const secret = 'web-billing-secret-must-not-enter-json';

        await storage.saveProviderWebBillingVariables('provider-a', {
          'AUTHORIZATION_TOKEN': secret,
        });

        expect(
          await store.read(
            ProviderKeyManager.webBillingVariableKeyFor(
              'provider-a',
              'AUTHORIZATION_TOKEN',
            ),
          ),
          secret,
        );
        expect(config().toJson().toString(), isNot(contains(secret)));
      },
    );

    test(
      'keeps generic variable namespaces isolated by provider and variable',
      () async {
        final store = InMemorySecureKeyStore();
        final manager = ProviderKeyManager(store);

        await manager.saveWebBillingVariable(
          providerId: 'provider-a',
          variableId: 'TOKEN',
          submittedValue: 'a-token',
        );
        await manager.saveWebBillingVariable(
          providerId: 'provider-b',
          variableId: 'TOKEN',
          submittedValue: 'b-token',
        );

        expect(
          await manager.readWebBillingVariable(
            providerId: 'provider-a',
            variableId: 'TOKEN',
          ),
          'a-token',
        );
        expect(
          await manager.readWebBillingVariable(
            providerId: 'provider-b',
            variableId: 'TOKEN',
          ),
          'b-token',
        );
      },
    );

    test(
      'returns length-preserving secret masks without returning secret text',
      () async {
        final store = InMemorySecureKeyStore()
          ..values[ProviderKeyManager.keyFor('provider-a')] = 'api-secret'
          ..values[ProviderKeyManager.webBillingVariableKeyFor(
                'provider-a',
                'TOKEN',
              )] =
              'generic-secret';
        final manager = ProviderKeyManager(store);

        expect(
          await manager.readProviderApiKeyMask('provider-a'),
          '••••••••••',
        );
        expect(
          await manager.readWebBillingVariableMasks(
            providerId: 'provider-a',
            variableIds: const ['TOKEN'],
          ),
          {'TOKEN': '••••••••••••••'},
        );
      },
    );

    test(
      'migrates a JSON API key to secure storage and removes it from JSON',
      () async {
        final store = InMemorySecureKeyStore();
        final manager = ProviderKeyManager(store);
        final migrated = await manager.hydrateAndMigrate(
          AppSnapshot(providerConfigs: [config(apiKey: 'legacy-value')]),
        );

        expect(migrated.pendingLegacyKeys, isEmpty);
        expect(migrated.snapshot.providerConfigs.single.apiKey, 'legacy-value');
        expect(
          migrated.snapshot.toJson().toString(),
          isNot(contains('legacy-value')),
        );
        expect(
          await store.read(ProviderKeyManager.keyFor('provider-a')),
          'legacy-value',
        );
      },
    );

    test(
      'migration failure preserves the JSON API key for a later retry',
      () async {
        final manager = ProviderKeyManager(
          InMemorySecureKeyStore()..failWrites = true,
        );
        final migrated = await manager.hydrateAndMigrate(
          AppSnapshot(providerConfigs: [config(apiKey: 'legacy-value')]),
        );

        expect(migrated.pendingLegacyKeys, {'provider-a': 'legacy-value'});
        expect(migrated.snapshot.providerConfigs.single.apiKey, 'legacy-value');
      },
    );

    test('writes and verifies a new provider API key', () async {
      final store = InMemorySecureKeyStore();
      final manager = ProviderKeyManager(store);

      final resolved = await manager.saveForProvider(
        id: 'provider-a',
        submittedKey: 'new-value',
        existingKey: '',
      );

      expect(resolved, 'new-value');
      expect(
        await store.read(ProviderKeyManager.keyFor('provider-a')),
        'new-value',
      );
    });

    test('blank API-key edit preserves the existing secure value', () async {
      final store = InMemorySecureKeyStore()
        ..values[ProviderKeyManager.keyFor('provider-a')] = 'stored-value';
      final manager = ProviderKeyManager(store);

      final resolved = await manager.saveForProvider(
        id: 'provider-a',
        submittedKey: '',
        existingKey: 'stored-value',
      );

      expect(resolved, 'stored-value');
    });

    test(
      'API_KEY prefers its generic value and otherwise uses provider key',
      () async {
        final store = InMemorySecureKeyStore()
          ..values[ProviderKeyManager.keyFor('provider-a')] = 'provider-value'
          ..values[ProviderKeyManager.webBillingVariableKeyFor(
                'provider-a',
                'API_KEY',
              )] =
              'generic-value';
        final manager = ProviderKeyManager(store);

        expect(
          await manager.readWebBillingVariable(
            providerId: 'provider-a',
            variableId: 'API_KEY',
          ),
          'generic-value',
        );
        store.values.remove(
          ProviderKeyManager.webBillingVariableKeyFor('provider-a', 'API_KEY'),
        );
        expect(
          await manager.readWebBillingVariable(
            providerId: 'provider-a',
            variableId: 'API_KEY',
          ),
          'provider-value',
        );
      },
    );

    test(
      'recognized legacy secret migration does not replace a generic value',
      () async {
        final genericKey = ProviderKeyManager.webBillingVariableKeyFor(
          'deepseek',
          'DEEPSEEK_API_KEY',
        );
        final store = InMemorySecureKeyStore()
          ..values[ProviderKeyManager.keyFor('deepseek')] = 'legacy-value'
          ..values[genericKey] = 'new-value';
        final manager = ProviderKeyManager(store);

        await manager.hydrateAndMigrate(
          AppSnapshot(
            providerConfigs: [
              config(
                id: 'deepseek',
                webBillingConfig: deepSeekWebBillingConfig(),
              ),
            ],
          ),
        );

        expect(store.values[genericKey], 'new-value');
      },
    );

    test(
      'delete removes known and declared secrets without crossing scopes',
      () async {
        final store = InMemorySecureKeyStore();
        for (final key in [
          ProviderKeyManager.keyFor('provider-a'),
          ProviderKeyManager.balanceTokenKeyFor('provider-a'),
          ProviderKeyManager.billCookieKeyFor('provider-a'),
          ProviderKeyManager.walletCookieKeyFor('provider-a'),
          ProviderKeyManager.walletSubjectIdKeyFor('provider-a'),
          ProviderKeyManager.webBillingVariableKeyFor('provider-a', 'TOKEN'),
          ProviderKeyManager.webBillingVariableKeyFor('provider-a', 'COOKIE'),
          ProviderKeyManager.keyFor('provider-b'),
          ProviderKeyManager.webBillingVariableKeyFor('provider-b', 'TOKEN'),
        ]) {
          store.values[key] = 'stored-value';
        }
        final manager = ProviderKeyManager(store);

        await manager.deleteForProvider(
          'provider-a',
          declaredWebBillingVariableIds: const ['TOKEN'],
        );

        expect(store.values[ProviderKeyManager.keyFor('provider-a')], isNull);
        expect(
          store.values[ProviderKeyManager.balanceTokenKeyFor('provider-a')],
          isNull,
        );
        expect(
          store.values[ProviderKeyManager.billCookieKeyFor('provider-a')],
          isNull,
        );
        expect(
          store.values[ProviderKeyManager.walletCookieKeyFor('provider-a')],
          isNull,
        );
        expect(
          store.values[ProviderKeyManager.walletSubjectIdKeyFor('provider-a')],
          isNull,
        );
        expect(
          store.values[ProviderKeyManager.webBillingVariableKeyFor(
            'provider-a',
            'TOKEN',
          )],
          isNull,
        );
        expect(
          store.values[ProviderKeyManager.webBillingVariableKeyFor(
            'provider-a',
            'COOKIE',
          )],
          'stored-value',
        );
        expect(
          store.values[ProviderKeyManager.keyFor('provider-b')],
          'stored-value',
        );
        expect(
          store.values[ProviderKeyManager.webBillingVariableKeyFor(
            'provider-b',
            'TOKEN',
          )],
          'stored-value',
        );
      },
    );

    test('delete removes the secure provider API key', () async {
      final store = InMemorySecureKeyStore()
        ..values[ProviderKeyManager.keyFor('provider-a')] = 'stored-value';
      final manager = ProviderKeyManager(store);

      await manager.deleteForProvider('provider-a');

      expect(await store.read(ProviderKeyManager.keyFor('provider-a')), isNull);
    });
  });
}
