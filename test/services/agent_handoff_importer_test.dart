import 'dart:convert';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/services/agent_handoff_importer.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySecrets implements SecureKeyStore {
  final values = <String, String>{};
  String? failKey;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (key == failKey) throw StateError('write failed');
    values[key] = value;
  }
}

Map<String, Object?> artifact({String action = 'configure_web_billing'}) => {
  'schema_version': '1.0',
  'action': action,
  'provider': {
    'id': 'example',
    'name': 'Example Billing',
    'base_url': 'https://example.test',
  },
  'request_templates': [
    {
      'id': 'account',
      'method': 'GET',
      'url_template': 'https://example.test/api/account',
      'headers_template': {'Authorization': r'Bearer ${TOKEN}'},
      'query_template': <String, String>{},
    },
  ],
  'secret_variables': [
    {
      'name': 'TOKEN',
      'display_name': 'Account token',
      'type': 'bearer_token',
      'required': true,
    },
  ],
  'metric_rules': [
    {
      'id': 'balance',
      'kind': 'balance',
      'request_template_id': 'account',
      'response_path': r'$.data.balance',
      'multiplier': 1,
      'divisor': 100,
      'unit': '元',
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'agent_battery_state_v1': jsonEncode(const AppSnapshot().toJson()),
    });
  });

  test(
    'imports provider config and stores secret outside snapshot JSON',
    () async {
      final secrets = MemorySecrets();
      final storage = StorageService(keyStore: secrets);
      final importer = AgentHandoffImporter(storage);

      final result = await importer.import(
        artifact(),
        secretValues: const {'TOKEN': 'sentinel-secret'},
      );

      expect(result.providerId, 'example');
      expect(result.configuredMetrics, ['balance']);
      final snapshot = await storage.load();
      final provider = snapshot.providerConfigs.singleWhere(
        (p) => p.id == 'example',
      );
      expect(provider.name, 'Example Billing');
      expect(
        provider.webBillingConfig!.requestTemplates.single.urlTemplate,
        'https://example.test/api/account',
      );
      expect(
        provider.webBillingConfig!.metricRules.single.responseRule.scalarPath,
        'data.balance',
      );
      expect(
        secrets.values[ProviderKeyManager.webBillingVariableKeyFor(
          'example',
          'TOKEN',
        )],
        'sentinel-secret',
      );
      final persisted = (await SharedPreferences.getInstance()).getString(
        'agent_battery_state_v1',
      )!;
      expect(persisted, isNot(contains('sentinel-secret')));
    },
  );

  test(
    'rejects missing and undeclared secret values without echoing values',
    () async {
      final importer = AgentHandoffImporter(
        StorageService(keyStore: MemorySecrets()),
      );

      await expectLater(
        importer.import(artifact(), secretValues: const {}),
        throwsA(
          isA<AgentHandoffImportException>().having(
            (e) => e.message,
            'message',
            allOf(contains('TOKEN'), isNot(contains('sentinel'))),
          ),
        ),
      );
      await expectLater(
        importer.import(
          artifact(),
          secretValues: const {'TOKEN': 'sentinel', 'EXTRA': 'other-secret'},
        ),
        throwsA(
          isA<AgentHandoffImportException>().having(
            (e) => e.message,
            'message',
            allOf(contains('EXTRA'), isNot(contains('other-secret'))),
          ),
        ),
      );
    },
  );

  test('restores earlier secrets when a later secure write fails', () async {
    final raw = artifact();
    (raw['secret_variables'] as List).add({
      'name': 'COOKIE',
      'display_name': 'Cookie',
      'type': 'cookie_header',
      'required': true,
    });
    final secrets = MemorySecrets();
    final tokenKey = ProviderKeyManager.webBillingVariableKeyFor(
      'example',
      'TOKEN',
    );
    final cookieKey = ProviderKeyManager.webBillingVariableKeyFor(
      'example',
      'COOKIE',
    );
    secrets.values[tokenKey] = 'old-token';
    secrets.failKey = cookieKey;
    final importer = AgentHandoffImporter(StorageService(keyStore: secrets));

    await expectLater(
      importer.import(
        raw,
        secretValues: const {'TOKEN': 'new-token', 'COOKIE': 'new-cookie'},
      ),
      throwsA(isA<AgentHandoffImportException>()),
    );
    expect(secrets.values[tokenKey], 'old-token');
  });

  test('credential renewal changes only declared secrets', () async {
    final secrets = MemorySecrets();
    final storage = StorageService(keyStore: secrets);
    final importer = AgentHandoffImporter(storage);
    await importer.import(
      artifact(),
      secretValues: const {'TOKEN': 'old-token'},
    );
    final before = await storage.load();
    final renewal = artifact(action: 'renew_credentials')
      ..['credential_renewal'] = {
        'required_variables': ['TOKEN'],
        'documentation': 'Manual session renewal.',
        'preserve_billing_rules': true,
      };

    await importer.import(renewal, secretValues: const {'TOKEN': 'new-token'});

    final after = await storage.load();
    expect(
      after.providerConfigs.single.toJson(),
      before.providerConfigs.single.toJson(),
    );
    expect(
      secrets.values[ProviderKeyManager.webBillingVariableKeyFor(
        'example',
        'TOKEN',
      )],
      'new-token',
    );
  });
}
