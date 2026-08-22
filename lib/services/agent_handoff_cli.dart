import 'dart:convert';
import 'dart:io';

import '../models/agent_handoff.dart';

typedef AgentHandoffWriteLine = void Function(Object? line);

Future<int> runAgentHandoffValidatorCli(
  List<String> arguments, {
  AgentHandoffWriteLine? writeLine,
}) async {
  final write = writeLine ?? stdout.writeln;
  if (arguments.length != 1) {
    write('Usage: dart run tools/validate_agent_handoff.dart <artifact.json>');
    return 2;
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

  final result = const AgentHandoffValidator().validate(decoded);
  if (result.isValid) {
    write('VALID: Agent handoff artifact passed validation.');
    return 0;
  }

  write(
    'INVALID: Agent handoff artifact has ${result.issues.length} issue(s).',
  );
  for (final issue in result.issues) {
    write(issue);
  }
  return 1;
}
