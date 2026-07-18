import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
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

ProviderConfig config({String apiKey = ''}) => ProviderConfig(
  id: 'provider-a',
  name: 'Provider A',
  colorValue: 0xff123456,
  order: 0,
  enabled: true,
  baseUrl: 'https://example.invalid/v1',
  apiKey: apiKey,
);

void main() {
  group('ProviderKeyManager', () {
    test('migrates a legacy key and projects JSON without it', () async {
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
    });

    test('migration failure preserves the legacy key for a later retry', () async {
      final manager = ProviderKeyManager(
        InMemorySecureKeyStore()..failWrites = true,
      );
      final migrated = await manager.hydrateAndMigrate(
        AppSnapshot(providerConfigs: [config(apiKey: 'legacy-value')]),
      );

      expect(migrated.pendingLegacyKeys, {'provider-a': 'legacy-value'});
      expect(migrated.snapshot.providerConfigs.single.apiKey, 'legacy-value');
    });

    test('writes and verifies a new provider key', () async {
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

    test('blank edit preserves the existing secure key', () async {
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

    test('stores PuCoding dashboard JWT separately from the API key', () async {
      final store = InMemorySecureKeyStore();
      final manager = ProviderKeyManager(store);

      final token = await manager.saveBalanceToken(
        id: 'pucoding',
        submittedToken: 'dashboard-jwt',
        existingToken: '',
      );

      expect(token, 'dashboard-jwt');
      expect(
        await store.read(ProviderKeyManager.balanceTokenKeyFor('pucoding')),
        'dashboard-jwt',
      );
      expect(await store.read(ProviderKeyManager.keyFor('pucoding')), isNull);
    });

    test('removes an optional Bearer prefix before secure storage', () async {
      final store = InMemorySecureKeyStore();
      final manager = ProviderKeyManager(store);

      await manager.saveBalanceToken(
        id: 'pucoding',
        submittedToken: 'Bearer dashboard-jwt',
        existingToken: '',
      );

      expect(
        await store.read(ProviderKeyManager.balanceTokenKeyFor('pucoding')),
        'dashboard-jwt',
      );
    });

    test('hydrates a stored balance token when the provider has a legacy API key', () async {
      final store = InMemorySecureKeyStore()
        ..values[ProviderKeyManager.balanceTokenKeyFor('pucoding')] =
            'dashboard-jwt';
      final manager = ProviderKeyManager(store);

      final hydrated = await manager.hydrateAndMigrate(
        AppSnapshot(
          providerConfigs: [config(apiKey: 'legacy-model-key').copyWith(id: 'pucoding')],
        ),
      );

      expect(hydrated.snapshot.providerConfigs.single.balanceToken, 'dashboard-jwt');
    });

    test('delete removes the secure provider key', () async {
      final store = InMemorySecureKeyStore()
        ..values[ProviderKeyManager.keyFor('provider-a')] = 'stored-value';
      final manager = ProviderKeyManager(store);

      await manager.deleteForProvider('provider-a');

      expect(await store.read(ProviderKeyManager.keyFor('provider-a')), isNull);
    });
  });
}
