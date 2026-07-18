import 'dart:convert';

import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/hermes_provider_importer.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:agent_battery_flutter/ui/screens/provider_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureKeyStore implements SecureKeyStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  testWidgets(
    'Hermes import rebuilds management list with saved key state without persisting the key in JSON',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const apiKey = 'imported-hermes-key';
      const importedConfig = ProviderConfig(
        id: 'hermes-provider',
        name: 'Hermes Provider',
        colorValue: 0xff365edc,
        order: 0,
        enabled: true,
        baseUrl: 'https://hermes.example/v1',
      );
      final keys = _MemorySecureKeyStore();
      final controller = BatteryController(
        storage: StorageService(keyStore: keys),
        api: ApiClient(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ProviderManagementScreen(controller: controller)),
      );

      await controller.importHermesProviders(
        const HermesImportPlan([
          HermesImportedProvider(config: importedConfig, apiKey: apiKey),
        ]),
      );
      await tester.pump();

      expect(find.text('Hermes Provider'), findsOneWidget);
      expect(find.textContaining('Key：未配置'), findsNothing);
      expect(
        find.textContaining('Key：${controller.configs.single.maskedApiKey}'),
        findsOneWidget,
      );
      expect(keys.values[ProviderKeyManager.keyFor('hermes-provider')], apiKey);

      final preferences = await SharedPreferences.getInstance();
      final persisted = preferences.getString('agent_battery_state_v1')!;
      expect(jsonDecode(persisted), isA<Map<String, dynamic>>());
      expect(persisted, isNot(contains(apiKey)));
    },
  );
}
