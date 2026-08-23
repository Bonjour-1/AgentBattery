import 'package:agent_battery_flutter/models/agent_handoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> validArtifact() => {
    'schema_version': '1.0',
    'action': 'configure_web_billing',
    'provider': {
      'id': 'example-provider',
      'name': 'Example Provider',
      'base_url': 'https://api.example.test',
    },
    'request_templates': [
      {
        'id': 'billing',
        'method': 'GET',
        'url_template': 'https://api.example.test/billing',
        'headers_template': {'Authorization': r'Bearer ${BILLING_TOKEN}'},
        'query_template': <String, String>{},
      },
    ],
    'secret_variables': [
      {
        'name': 'BILLING_TOKEN',
        'display_name': 'Billing token',
        'type': 'bearer_token',
        'required': true,
      },
    ],
    'metric_rules': [
      {
        'id': 'balance',
        'kind': 'balance',
        'request_template_id': 'billing',
        'response_path': r'$.data.balance',
        'multiplier': 1,
        'divisor': 1,
      },
    ],
  };

  AgentHandoffValidationResult validate(Map<String, Object?> artifact) =>
      const AgentHandoffValidator().validate(artifact);

  test('accepts a valid handoff artifact', () {
    final result = validate(validArtifact());

    expect(result.isValid, isTrue);
    expect(result.issues, isEmpty);
  });

  test('accepts an HTTP recharge URL and rejects non-HTTP values', () {
    final artifact = validArtifact();
    final provider = artifact['provider']! as Map<String, Object?>;
    provider['recharge_url'] = 'https://example.test/recharge';
    expect(validate(artifact).isValid, isTrue);

    provider['recharge_url'] = 'javascript:alert(1)';
    expect(
      validate(artifact).issues.map((issue) => issue.code),
      contains('recharge_url'),
    );
  });

  test('rejects unsupported versions, actions, methods, and non-HTTP URLs', () {
    final artifact = validArtifact();
    artifact['schema_version'] = '2.0';
    artifact['action'] = 'run_shell';
    final request = (artifact['request_templates']! as List).single as Map;
    request['method'] = 'DELETE';
    request['url_template'] = 'file:///etc/passwd';

    final codes = validate(artifact).issues.map((issue) => issue.code);

    expect(codes, containsAll(['schema_version', 'action', 'method', 'url']));
  });

  test('rejects duplicate identifiers and broken metric references', () {
    final artifact = validArtifact();
    final requests = artifact['request_templates']! as List;
    requests.add(Map<String, Object>.from(requests.single as Map));
    final secrets = artifact['secret_variables']! as List;
    secrets.add(Map<String, Object>.from(secrets.single as Map));
    final metric = (artifact['metric_rules']! as List).single as Map;
    metric['request_template_id'] = 'missing';

    final codes = validate(artifact).issues.map((issue) => issue.code);

    expect(
      codes,
      containsAll([
        'duplicate_request_id',
        'duplicate_secret_name',
        'request_reference',
      ]),
    );
  });

  test('requires at least one valid metric with safe extraction scaling', () {
    final artifact = validArtifact();
    final metric = (artifact['metric_rules']! as List).single as Map;
    metric['kind'] = 'quota';
    metric['response_path'] = 'data.balance';
    metric['multiplier'] = 0;
    metric['divisor'] = double.nan;

    final codes = validate(artifact).issues.map((issue) => issue.code);

    expect(
      codes,
      containsAll(['metric_kind', 'response_path', 'multiplier', 'divisor']),
    );

    artifact['metric_rules'] = <Object?>[];
    expect(
      validate(artifact).issues.map((issue) => issue.code),
      contains('metric_required'),
    );
  });

  test('rejects literal credentials in headers, query, URL, and body', () {
    const sentinel = 'SENTINEL-super-secret-123';
    final artifact = validArtifact();
    final request = (artifact['request_templates']! as List).single as Map;
    request['headers_template'] = {
      'Authorization': 'Bearer $sentinel',
      'Cookie': 'session=$sentinel',
    };
    request['query_template'] = {'api_key': sentinel};
    request['url_template'] =
        'https://api.example.test/billing?token=$sentinel';
    request['body_template'] = '{"access_token":"$sentinel"}';

    final result = validate(artifact);

    expect(
      result.issues.map((issue) => issue.code),
      containsAll([
        'secret_literal_header',
        'secret_literal_query',
        'secret_literal_url',
        'secret_literal_body',
      ]),
    );
    expect(result.safeDiagnostics, isNot(contains(sentinel)));
    expect(result.issues.join('\n'), isNot(contains(sentinel)));
  });

  test('accepts declared placeholders in sensitive request locations', () {
    final artifact = validArtifact();
    final request = (artifact['request_templates']! as List).single as Map;
    request['headers_template'] = {
      'Authorization': r'Bearer ${BILLING_TOKEN}',
      'Cookie': r'session=${BILLING_TOKEN}',
    };
    request['query_template'] = {'api_key': r'${BILLING_TOKEN}'};
    request['url_template'] =
        r'https://api.example.test/billing?token=${BILLING_TOKEN}';
    request['body_template'] = r'{"access_token":"${BILLING_TOKEN}"}';

    expect(validate(artifact).isValid, isTrue);
  });

  test(
    'rejects sensitive literals even when another placeholder is present',
    () {
      final artifact = validArtifact();
      final request = (artifact['request_templates']! as List).single as Map;
      request['headers_template'] = {
        'Authorization': r'Bearer literal-secret ${BILLING_TOKEN}',
      };
      request['query_template'] = {
        'api_key': r'literal-secret-${BILLING_TOKEN}',
      };
      request['body_template'] =
          r'{"access_token":"literal-secret","other":"${BILLING_TOKEN}"}';

      expect(
        validate(artifact).issues.map((issue) => issue.code),
        containsAll([
          'secret_literal_header',
          'secret_literal_query',
          'secret_literal_body',
        ]),
      );
    },
  );

  test('accepts the runtime variables supported by the billing engine', () {
    final artifact = validArtifact();
    final request = (artifact['request_templates']! as List).single as Map;
    request['query_template'] = {
      'day_start': r'${DAY_START_UNIX_MS}',
      'month_start': r'${MONTH_START_DATE}',
      'current': r'${CURRENT_UNIX}',
      'utc_end': r'${UTC_MONTH_TO_DATE_END_UNIX}',
      'timezone': r'${TZ_HOURS}',
    };

    expect(validate(artifact).isValid, isTrue);
  });

  test(
    'rejects undeclared placeholders without echoing their names as values',
    () {
      final artifact = validArtifact();
      final request = (artifact['request_templates']! as List).single as Map;
      request['headers_template'] = {
        'Authorization': r'Bearer ${UNKNOWN_TOKEN}',
      };

      final result = validate(artifact);

      expect(
        result.issues.map((issue) => issue.code),
        contains('undeclared_variable'),
      );
    },
  );

  test('validates a secret-free credential renewal task', () {
    final artifact = validArtifact();
    artifact['action'] = 'renew_credentials';
    artifact['credential_renewal'] = {
      'required_variables': ['BILLING_TOKEN'],
      'documentation': 'AGENT_SETUP.md',
      'preserve_billing_rules': true,
    };
    expect(validate(artifact).isValid, isTrue);

    final renewal = artifact['credential_renewal']! as Map;
    renewal['required_variables'] = ['MISSING_TOKEN'];
    renewal['preserve_billing_rules'] = false;
    expect(
      validate(artifact).issues.map((issue) => issue.code),
      containsAll(['renewal_variable', 'preserve_billing_rules']),
    );
  });

  test('rejects unsafe processing expressions', () {
    final artifact = validArtifact();
    final metric = (artifact['metric_rules']! as List).single as Map;
    metric.remove('response_path');
    metric['processing_expression'] = 'system("whoami")';

    expect(
      validate(artifact).issues.map((issue) => issue.code),
      contains('processing_expression'),
    );
  });
}
