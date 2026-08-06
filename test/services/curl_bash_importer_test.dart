import 'dart:convert';

import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/curl_bash_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const importer = CurlBashImporter();

  test('GET browser cURL lifts bearer while retaining ordinary headers', () {
    const token = 'bearer...123';
    final result = importer.parse(
      """curl 'https://billing.example.test/usage' \\
  -H 'Authorization: Bearer bearer...123' \\
  -H 'Accept: application/json' \\
  -H 'Referer: https://app.example.test/'""",
    );

    expect(result.error, isNull);
    final draft = result.draft!;
    expect(draft.requestTemplate.method, 'GET');
    expect(
      draft.requestTemplate.urlTemplate,
      'https://billing.example.test/usage',
    );
    expect(draft.requestTemplate.headersTemplate['Accept'], 'application/json');
    expect(
      draft.requestTemplate.headersTemplate['Authorization'],
      'Bearer \${AUTHORIZATION_TOKEN}',
    );
    expect(draft.secretVariableDefinitions.single.name, 'AUTHORIZATION_TOKEN');
    final candidate = result.secretValueCandidates.single;
    expect(candidate.variableName, 'AUTHORIZATION_TOKEN');
    expect(candidate.value.length, 12);
    expect(candidate.maskedValue, '[REDACTED]');
    expect(
      candidate.toString(),
      'SecretValueCandidate('
      'variableName: AUTHORIZATION_TOKEN, value: [REDACTED])',
    );
    expect(jsonEncode(draft.toJson()), isNot(contains(token)));
  });

  test(
    'cookie input and x-subject-id are lifted without leaking into draft',
    () {
      const cookie = 'sid=cookie-secret; route=blue';
      const subject = 'private-subject-id';
      final result = importer.parse("""curl 'https://billing.example.test/me' \\
  -b 'sid=cookie-secret; route=blue' \\
  -H 'X-Subject-Id: private-subject-id' \\
  -H 'User-Agent: Mozilla/5.0'""");

      expect(result.error, isNull);
      final draft = result.draft!;
      expect(draft.requestTemplate.headersTemplate['Cookie'], r'${COOKIE}');
      expect(
        draft.requestTemplate.headersTemplate['X-Subject-Id'],
        r'${SUBJECT_ID}',
      );
      expect(
        draft.requestTemplate.headersTemplate['User-Agent'],
        'Mozilla/5.0',
      );
      expect(
        draft.secretVariableDefinitions.map((definition) => definition.name),
        containsAll(<String>['COOKIE', 'SUBJECT_ID']),
      );
      final encoded = jsonEncode(draft.toJson());
      expect(encoded, isNot(contains(cookie)));
      expect(encoded, isNot(contains(subject)));
    },
  );

  test(
    'POST JSON body maps API-key fields to the provider API_KEY variable',
    () {
      const key = 'body-api-key';
      final result = importer.parse(
        """curl 'https://billing.example.test/report' \\
  --data-raw '{"key":"body-api-key","page":2}' \\
  -H 'Content-Type: application/json'""",
      );

      expect(result.error, isNull);
      final draft = result.draft!;
      expect(draft.requestTemplate.method, 'POST');
      expect(
        draft.requestTemplate.bodyTemplate,
        r'{"key":"${API_KEY}","page":2}',
      );
      expect(draft.secretVariableDefinitions.single.name, 'API_KEY');
      expect(
        draft.secretVariableDefinitions.map((definition) => definition.name),
        isNot(contains('KEY')),
      );
      expect(jsonEncode(draft.toJson()), isNot(contains(key)));
    },
  );

  test('query API-key fields map to API_KEY', () {
    const key = 'query-api-key';
    final result = importer.parse(
      "curl 'https://billing.example.test/usage?api_key=query-api-key'",
    );

    expect(result.error, isNull);
    expect(result.draft!.requestTemplate.queryTemplate, {
      'api_key': r'${API_KEY}',
    });
    expect(result.draft!.secretVariableDefinitions.single.name, 'API_KEY');
    expect(jsonEncode(result.draft!.toJson()), isNot(contains(key)));
  });

  test('browser cURL --url option is accepted as the request URL', () {
    final result = importer.parse(
      """curl --url 'https://billing.example.test/usage?start=1710000000&end=1710003600' \\
  -H 'Accept: application/json'""",
    );

    expect(result.error, isNull);
    final request = result.draft!.requestTemplate;
    expect(request.method, 'GET');
    expect(request.urlTemplate, 'https://billing.example.test/usage');
    expect(request.queryTemplate, {
      'start': '1710000000',
      'end': '1710003600',
    });
    expect(request.headersTemplate['Accept'], 'application/json');
    expect(
      request.sourceCurl,
      "curl --url 'https://billing.example.test/usage?start=1710000000&end=1710003600' -H 'Accept: application/json'",
    );
  });

  test('common browser cURL transport options are tolerated', () {
    final result = importer.parse(
      """curl --compressed --location --globoff --url 'https://billing.example.test/usage' \\
  --user-agent 'Mozilla/5.0' \\
  --referer 'https://app.example.test/' \\
  --connect-timeout '10' \\
  --max-time '30' \\
  -H 'Accept: application/json'""",
    );

    expect(result.error, isNull);
    final request = result.draft!.requestTemplate;
    expect(request.urlTemplate, 'https://billing.example.test/usage');
    expect(request.headersTemplate['User-Agent'], 'Mozilla/5.0');
    expect(request.headersTemplate['Referer'], 'https://app.example.test/');
    expect(request.headersTemplate['Accept'], 'application/json');
  });

  test('source curl is retained with sensitive values redacted', () {
    const secret = 'private-subject-id';
    final result = importer.parse(
      """curl --url 'https://billing.example.test/usage?start=1710000000&token=$secret' \\
  -H 'X-Subject-Id: private-subject-id' \\
  -H 'Accept: application/json'""",
    );

    expect(result.error, isNull);
    final sourceCurl = result.draft!.requestTemplate.sourceCurl!;
    expect(sourceCurl, contains('curl --url'));
    expect(sourceCurl, contains(r'${TOKEN}'));
    expect(sourceCurl, contains(r'${SUBJECT_ID}'));
    expect(sourceCurl, isNot(contains(secret)));
    expect(
      RequestTemplate.fromJson(result.draft!.requestTemplate.toJson()).sourceCurl,
      sourceCurl,
    );
  });

  test('curl --url conflicts with a positional URL', () {
    final result = importer.parse(
      "curl --url 'https://billing.example.test/usage' 'https://other.example.test/usage'",
    );

    expect(result.draft, isNull);
    expect(result.error, 'Only one URL is supported.');
  });

  test('non-sensitive time query remains while sensitive token is lifted', () {
    const token = 'query-token';
    final result = importer.parse(
      "curl 'https://billing.example.test/usage?start=1710000000&end=1710003600&token=query-token'",
    );

    expect(result.error, isNull);
    final request = result.draft!.requestTemplate;
    expect(request.urlTemplate, 'https://billing.example.test/usage');
    expect(request.queryTemplate, {
      'start': '1710000000',
      'end': '1710003600',
      'token': r'${TOKEN}',
    });
    expect(result.draft!.secretVariableDefinitions.single.name, 'TOKEN');
    expect(jsonEncode(result.draft!.toJson()), isNot(contains(token)));
  });

  test('same header and body API key reuse one API_KEY definition', () {
    const key = 'same-api-key';
    final result = importer.parse(
      """curl 'https://billing.example.test/report' \\
  -H 'X-Api-Key: same-api-key' \\
  --data-raw '{"key":"same-api-key"}'""",
    );

    expect(result.error, isNull);
    final draft = result.draft!;
    expect(draft.requestTemplate.headersTemplate['X-Api-Key'], r'${API_KEY}');
    expect(draft.requestTemplate.bodyTemplate, r'{"key":"${API_KEY}"}');
    expect(
      draft.secretVariableDefinitions.map((definition) => definition.name),
      <String>['API_KEY'],
    );
    expect(result.secretValueCandidates, hasLength(1));
    expect(jsonEncode(draft.toJson()), isNot(contains(key)));
  });

  test('unsupported shell syntax is rejected without a draft', () {
    final result = importer.parse(
      "curl 'https://billing.example.test' -H 'Accept: x' | sh",
    );

    expect(result.draft, isNull);
    expect(result.secretValueCandidates, isEmpty);
    expect(result.error, isNotNull);
  });

  test(
    'sensitive header variable names are deterministic and collision-free',
    () {
      final result = importer.parse("""curl 'https://billing.example.test' \\
  -H 'Authorization: Bearer ***' \\
  -H 'X-Api-Key: api-key-value'""");

      expect(result.error, isNull);
      expect(
        result.draft!.secretVariableDefinitions.map(
          (definition) => definition.name,
        ),
        <String>['AUTHORIZATION_TOKEN', 'API_KEY'],
      );
    },
  );
}
