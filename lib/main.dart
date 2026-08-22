import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/agent_handoff_import_cli.dart';
import 'services/app_storage_scope.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppStorageScope.configureFromEntrypointArguments(arguments);
  if (arguments.firstOrNull == 'import-agent-handoff') {
    final importArguments = arguments
        .skip(1)
        .where((argument) => argument != '--agentbattery-test-variant')
        .toList();
    final result = await runAgentHandoffImporterCli(importArguments);
    exit(result);
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(680, 800),
      minimumSize: Size(620, 720),
      center: true,
      title: 'AgentBattery',
      backgroundColor: Color(0xff0d5753),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const AgentBatteryApp());
}
