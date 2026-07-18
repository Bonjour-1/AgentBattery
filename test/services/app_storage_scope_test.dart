import 'package:agent_battery_flutter/services/app_storage_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppStorageScope.configureFromEntrypointArguments(const []));

  test('test variant uses isolated state and secure-storage namespaces', () {
    AppStorageScope.configureFromEntrypointArguments(const [
      '--agentbattery-test-variant',
    ]);

    expect(AppStorageScope.isTestVariant, isTrue);
    expect(AppStorageScope.stateKey, AppStorageScope.testStateKey);
    expect(AppStorageScope.securePrefix, AppStorageScope.testSecurePrefix);
    expect(AppStorageScope.stateKey, isNot(AppStorageScope.productionStateKey));
    expect(
      AppStorageScope.securePrefix,
      isNot(AppStorageScope.productionSecurePrefix),
    );
  });

  test('default entrypoint keeps production storage namespaces', () {
    AppStorageScope.configureFromEntrypointArguments(const []);

    expect(AppStorageScope.isTestVariant, isFalse);
    expect(AppStorageScope.stateKey, AppStorageScope.productionStateKey);
    expect(
      AppStorageScope.securePrefix,
      AppStorageScope.productionSecurePrefix,
    );
  });
}
