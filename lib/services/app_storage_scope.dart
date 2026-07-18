/// Runtime storage namespace set by the Windows test runner or Dart define.
class AppStorageScope {
  const AppStorageScope._();

  static const productionStateKey = 'agent_battery_state_v1';
  static const testStateKey = 'agent_battery_test_state_v1';
  static const productionSecurePrefix = 'agentbattery/provider/';
  static const testSecurePrefix = 'agentbattery/test/provider/';
  static const _dartDefineTestVariant = bool.fromEnvironment(
    'AGENTBATTERY_TEST_VARIANT',
    defaultValue: false,
  );
  static bool _testVariant = _dartDefineTestVariant;

  static void configureFromEntrypointArguments(List<String> arguments) {
    _testVariant =
        _dartDefineTestVariant ||
        arguments.contains('--agentbattery-test-variant');
  }

  static bool get isTestVariant => _testVariant;
  static String get stateKey =>
      isTestVariant ? testStateKey : productionStateKey;
  static String get securePrefix =>
      isTestVariant ? testSecurePrefix : productionSecurePrefix;
}
