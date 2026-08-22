import 'dart:convert';
import 'dart:io';

import 'package:agent_battery_flutter/services/agent_handoff_cli.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CLI returns 0 for a valid artifact and prints no request values',
    () async {
      final directory = await Directory.systemTemp.createTemp('handoff-cli-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/valid.json');
      await file.writeAsString(
        jsonEncode({
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
              'query_template': <String, String>{},
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
        }),
      );
      final output = StringBuffer();

      final exitCode = await runAgentHandoffValidatorCli([
        file.path,
      ], writeLine: output.writeln);

      expect(exitCode, 0);
      expect(output.toString(), contains('VALID'));
    },
  );

  test(
    'CLI returns 1 with safe diagnostics for invalid JSON artifact',
    () async {
      const sentinel = 'SENTINEL-do-not-echo';
      final directory = await Directory.systemTemp.createTemp('handoff-cli-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/invalid.json');
      await file.writeAsString(
        jsonEncode({
          'schema_version': '1.0',
          'action': 'configure_web_billing',
          'provider': {'id': 'example', 'name': 'Example'},
          'request_templates': [
            {
              'id': 'billing',
              'method': 'GET',
              'url_template': 'https://example.test',
              'headers_template': {'Authorization': 'Bearer $sentinel'},
            },
          ],
          'metric_rules': <Object?>[],
          'secret_variables': <Object?>[],
        }),
      );
      final output = StringBuffer();

      final exitCode = await runAgentHandoffValidatorCli([
        file.path,
      ], writeLine: output.writeln);

      expect(exitCode, 1);
      expect(output.toString(), contains('INVALID'));
      expect(output.toString(), isNot(contains(sentinel)));
    },
  );

  test(
    'CLI rejects missing arguments and malformed JSON without throwing',
    () async {
      final usageOutput = StringBuffer();
      expect(
        await runAgentHandoffValidatorCli([], writeLine: usageOutput.writeln),
        2,
      );

      final directory = await Directory.systemTemp.createTemp('handoff-cli-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/broken.json');
      await file.writeAsString('{broken');
      final malformedOutput = StringBuffer();

      expect(
        await runAgentHandoffValidatorCli([
          file.path,
        ], writeLine: malformedOutput.writeln),
        1,
      );
      expect(malformedOutput.toString(), contains('INVALID'));
      expect(malformedOutput.toString(), isNot(contains('{broken')));
    },
  );
}
