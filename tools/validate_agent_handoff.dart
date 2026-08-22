import 'dart:io';

import 'package:agent_battery_flutter/services/agent_handoff_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runAgentHandoffValidatorCli(arguments);
}
