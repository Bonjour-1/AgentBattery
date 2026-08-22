import 'dart:convert';
import 'dart:io';

import '../models/agent_handoff.dart';
import 'agent_handoff_importer.dart';
import 'storage_service.dart';

typedef AgentHandoffImportWriteLine = void Function(Object? line);
typedef AgentHandoffSecretReader =
    Future<String?> Function(String variableName);

Future<int> runAgentHandoffImporterCli(
  List<String> arguments, {
  AgentHandoffImportWriteLine? writeLine,
  AgentHandoffSecretReader? readSecret,
  StorageService? storage,
  bool requireClosedProcess = true,
}) async {
  final write = writeLine ?? stdout.writeln;
  if (arguments.length != 1) {
    write('Usage: AgentBattery.exe import-agent-handoff <artifact.json>');
    return 2;
  }
  if (requireClosedProcess && await _isAnotherAgentBatteryProcessRunning()) {
    write('REFUSED: AgentBattery must be fully closed before import.');
    return 3;
  }

  Object? decoded;
  try {
    decoded = jsonDecode(await File(arguments.single).readAsString());
  } on FileSystemException {
    write('INVALID: artifact could not be read.');
    return 1;
  } on FormatException {
    write('INVALID: artifact is not valid JSON.');
    return 1;
  }
  final validation = const AgentHandoffValidator().validate(decoded);
  if (!validation.isValid) {
    write('INVALID: artifact has ${validation.issues.length} issue(s).');
    for (final issue in validation.issues) {
      write(issue);
    }
    return 1;
  }

  final artifact = Map<String, Object?>.from(decoded! as Map);
  final definitions = (artifact['secret_variables']! as List).map(
    (item) => Map<String, Object?>.from(item as Map),
  );
  final action = artifact['action']! as String;
  final requestedNames = action == 'renew_credentials'
      ? (Map<String, Object?>.from(
                  artifact['credential_renewal']! as Map,
                )['required_variables']!
                as List)
            .cast<String>()
            .toSet()
      : definitions.map((definition) => definition['name']! as String).toSet();
  final reader = readSecret ?? _readSecretFromStdin;
  final values = <String, String>{};
  for (final definition in definitions) {
    final name = definition['name']! as String;
    if (!requestedNames.contains(name)) continue;
    final value = await reader(name);
    if (value?.isNotEmpty == true) values[name] = value!;
  }

  try {
    final result = await AgentHandoffImporter(
      storage ?? StorageService(),
    ).import(artifact, secretValues: values);
    write(
      'IMPORTED: provider=${result.providerId} '
      'metrics=${result.configuredMetrics.join(',')} '
      'credentials=stored-securely.',
    );
    return 0;
  } on AgentHandoffImportException catch (error) {
    write('FAILED: ${error.message}');
    return 1;
  } catch (_) {
    write('FAILED: import did not complete.');
    return 1;
  }
}

Future<String?> _readSecretFromStdin(String variableName) async {
  stderr.write('Enter $variableName (input hidden): ');
  if (!stdin.hasTerminal) return stdin.readLineSync();
  stdin.echoMode = false;
  try {
    return stdin.readLineSync();
  } finally {
    stdin.echoMode = true;
    stderr.writeln();
  }
}

Future<bool> _isAnotherAgentBatteryProcessRunning() async {
  if (!Platform.isWindows) return false;
  final importPid = pid;
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-Command',
    r'$running = Get-Process AgentBattery -ErrorAction SilentlyContinue | '
        'Where-Object { ${r'$PSItem'}.Id -ne $importPid }; '
        r'if ($running) { exit 10 } else { exit 0 }',
  ]);
  return result.exitCode == 10;
}
