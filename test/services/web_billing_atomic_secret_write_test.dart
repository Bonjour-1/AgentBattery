import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingStore implements SecureKeyStore {
  final values = <String, String>{};
  String? failKey;
  String? failReadKey;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async {
    if (key == failReadKey) throw StateError('read failed');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (key == failKey) throw StateError('write failed');
    values[key] = value;
  }
}

void main() {
  test('atomic replacement writes every refreshed credential', () async {
    final store = FailingStore();
    final manager = ProviderKeyManager(store);

    await manager.replaceWebBillingVariablesAtomically(
      providerId: 'example',
      values: const {'ACCESS': 'new-access', 'REFRESH': 'new-refresh'},
    );

    expect(
      store.values[ProviderKeyManager.webBillingVariableKeyFor(
        'example',
        'ACCESS',
      )],
      'new-access',
    );
    expect(
      store.values[ProviderKeyManager.webBillingVariableKeyFor(
        'example',
        'REFRESH',
      )],
      'new-refresh',
    );
  });

  test(
    'atomic replacement aborts before writes when original read fails',
    () async {
      final store = FailingStore();
      final manager = ProviderKeyManager(store);
      final accessKey = ProviderKeyManager.webBillingVariableKeyFor(
        'example',
        'ACCESS',
      );
      store.values[accessKey] = 'old-access';
      store.failReadKey = accessKey;

      await expectLater(
        manager.replaceWebBillingVariablesAtomically(
          providerId: 'example',
          values: const {'ACCESS': 'new-access'},
        ),
        throwsStateError,
      );

      expect(store.values[accessKey], 'old-access');
    },
  );

  test(
    'atomic replacement restores all original credentials on failure',
    () async {
      final store = FailingStore();
      final manager = ProviderKeyManager(store);
      final accessKey = ProviderKeyManager.webBillingVariableKeyFor(
        'example',
        'ACCESS',
      );
      final refreshKey = ProviderKeyManager.webBillingVariableKeyFor(
        'example',
        'REFRESH',
      );
      store.values[accessKey] = 'old-access';
      store.values[refreshKey] = 'old-refresh';
      store.failKey = refreshKey;

      await expectLater(
        manager.replaceWebBillingVariablesAtomically(
          providerId: 'example',
          values: const {'ACCESS': 'new-access', 'REFRESH': 'new-refresh'},
        ),
        throwsStateError,
      );

      expect(store.values[accessKey], 'old-access');
      expect(store.values[refreshKey], 'old-refresh');
    },
  );
}
