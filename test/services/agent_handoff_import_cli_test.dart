import 'dart:convert';
import 'dart:io';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/services/agent_handoff_import_cli.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySecrets implements SecureKeyStore {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Map<String, Object?> artifact() => {
  'schema_version': '1.0',
  'action': 'configure_web_billing',
  'provider': {
    'id': 'example',
    'name': 'Example',
    'base_url': 'https://example.test',
  },
  'request_templates': [
    {
      'id': 'billing',
      'method': 'GET',
      'url_template': 'https://example.test/billing',
      'headers_template': {'Authorization': r'Bearer ${TOKEN}'},
    },
  ],
  'secret_variables': [
    {
      'name': 'TOKEN',
      'display_name': 'Token',
      'type': 'bearer_token',
      'required': true,
    },
  ],
  'metric_rules': [
    {
      'id': 'balance',
      'kind': 'balance',
      'request_template_id': 'billing',
      'response_path': r'$.balance',
      'multiplier': 1,
      'divisor': 1,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CLI imports through secret reader without echoing secret', () async {
    SharedPreferences.setMockInitialValues({
      'agent_battery_state_v1': jsonEncode(const AppSnapshot().toJson()),
    });
    final directory = await Directory.systemTemp.createTemp('handoff-import-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/artifact.json');
    await file.writeAsString(jsonEncode(artifact()));
    final output = StringBuffer();
    final secrets = MemorySecrets();

    final code = await runAgentHandoffImporterCli(
      [file.path],
      writeLine: output.writeln,
      readSecret: (name) async => 'sentinel-secret',
      storage: StorageService(keyStore: secrets),
      requireClosedProcess: false,
    );

    expect(code, 0);
    expect(output.toString(), contains('IMPORTED: provider=example'));
    expect(output.toString(), isNot(contains('sentinel-secret')));
  });

  test('CLI reports missing secret by name only', () async {
    SharedPreferences.setMockInitialValues({
      'agent_battery_state_v1': jsonEncode(const AppSnapshot().toJson()),
    });
    final directory = await Directory.systemTemp.createTemp('handoff-import-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/artifact.json');
    await file.writeAsString(jsonEncode(artifact()));
    final output = StringBuffer();

    final code = await runAgentHandoffImporterCli(
      [file.path],
      writeLine: output.writeln,
      readSecret: (name) async => null,
      storage: StorageService(keyStore: MemorySecrets()),
      requireClosedProcess: false,
    );

    expect(code, 1);
    expect(output.toString(), contains('TOKEN'));
  });
}
