import 'dart:async';
import 'dart:convert';

import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/web_billing_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const access = SecretVariableDefinition(
    id: 'access',
    name: 'ACCESS_TOKEN',
    displayName: 'Access token',
    type: SecretVariableType.bearerToken,
    required: true,
  );
  const refresh = SecretVariableDefinition(
    id: 'refresh',
    name: 'REFRESH_TOKEN',
    displayName: 'Refresh token',
    type: SecretVariableType.genericBodyValue,
    required: true,
  );
  final refreshConfig = CredentialRefreshConfig(
    triggerStatusCodes: [401, 403],
    requestTemplate: RequestTemplate(
      id: 'refresh_credentials',
      method: 'POST',
      urlTemplate: 'https://example.test/api/refresh',
      bodyTemplate: r'{"refreshToken":"${REFRESH_TOKEN}"}',
      headersTemplate: {'Content-Type': 'application/json'},
    ),
    responseVariablePaths: {
      'ACCESS_TOKEN': r'$.data.token',
      'REFRESH_TOKEN': r'$.data.refresh_token',
    },
  );

  WebBillingConfig config() => WebBillingConfig(
    schemaVersion: 1,
    secretVariableDefinitions: const [access, refresh],
    requestTemplates: const [
      RequestTemplate(
        id: 'balance',
        method: 'GET',
        urlTemplate: 'https://example.test/api/balance',
        headersTemplate: {'Authorization': r'Bearer ${ACCESS_TOKEN}'},
      ),
    ],
    metricRules: [
      MetricRule(
        id: 'balance',
        kind: WebBillingMetricKind.balance,
        requestTemplateId: 'balance',
        responseRule: const ResponseRule(scalarPath: 'data.balance'),
      ),
    ],
    credentialRefresh: refreshConfig,
  );

  test(
    '401 refreshes, securely writes both variables, and retries once',
    () async {
      final secrets = {
        'ACCESS_TOKEN': 'expired-access',
        'REFRESH_TOKEN': 'old-refresh',
      };
      final sent = <RawHttpRequest>[];
      final writes = <Map<String, String>>[];
      final engine = WebBillingEngine(
        secretResolver: (_, name) async => secrets[name],
        secretWriter: (_, values) async {
          writes.add(Map.of(values));
          secrets.addAll(values);
        },
        transport: (request) async {
          sent.add(request);
          if (request.uri.path.endsWith('/refresh')) {
            expect(jsonDecode(request.body!), {'refreshToken': 'old-refresh'});
            return const WebBillingHttpResponse(
              200,
              '{"data":{"token":"new-access","refresh_token":"new-refresh"}}',
            );
          }
          if (request.headers['Authorization'] == 'Bearer expired-access') {
            return const WebBillingHttpResponse(401, '{}');
          }
          return const WebBillingHttpResponse(200, '{"data":{"balance":12}}');
        },
      );

      final result = await engine.execute(
        providerId: 'generic',
        config: config(),
      );

      expect(result.balance.value, 12);
      expect(sent, hasLength(3));
      expect(writes, [
        {'ACCESS_TOKEN': 'new-access', 'REFRESH_TOKEN': 'new-refresh'},
      ]);
    },
  );

  test(
    'failed refresh does not write and original request is not retried',
    () async {
      var billingCalls = 0;
      var writes = 0;
      final engine = WebBillingEngine(
        secretResolver: (_, name) async =>
            name == 'ACCESS_TOKEN' ? 'expired' : 'bad-refresh',
        secretWriter: (_, values) async => writes++,
        transport: (request) async {
          if (request.uri.path.endsWith('/refresh')) {
            return const WebBillingHttpResponse(401, '{"private":"ignored"}');
          }
          billingCalls++;
          return const WebBillingHttpResponse(401, '{}');
        },
      );

      final result = await engine.execute(
        providerId: 'generic',
        config: config(),
      );

      expect(result.balance.succeeded, isFalse);
      expect(result.balance.failure, '账单认证刷新失败');
      expect(billingCalls, 1);
      expect(writes, 0);
    },
  );

  test('a retried 401 is not refreshed or retried again', () async {
    final secrets = {'ACCESS_TOKEN': 'expired', 'REFRESH_TOKEN': 'refresh'};
    var billingCalls = 0;
    var refreshCalls = 0;
    final engine = WebBillingEngine(
      secretResolver: (_, name) async => secrets[name],
      secretWriter: (_, values) async => secrets.addAll(values),
      transport: (request) async {
        if (request.uri.path.endsWith('/refresh')) {
          refreshCalls++;
          return const WebBillingHttpResponse(
            200,
            '{"data":{"token":"still-bad","refresh_token":"next"}}',
          );
        }
        billingCalls++;
        return const WebBillingHttpResponse(401, '{}');
      },
    );

    final result = await engine.execute(
      providerId: 'generic',
      config: config(),
    );

    expect(result.balance.failure, '账单请求 HTTP 401');
    expect(refreshCalls, 1);
    expect(billingCalls, 2);
  });

  test('a stale late 401 retries with already refreshed credentials', () async {
    final secrets = {'ACCESS_TOKEN': 'expired', 'REFRESH_TOKEN': 'refresh'};
    final lateResponse = Completer<void>();
    var expiredCalls = 0;
    var refreshCalls = 0;
    final engine = WebBillingEngine(
      secretResolver: (_, name) async => secrets[name],
      secretWriter: (_, values) async => secrets.addAll(values),
      transport: (request) async {
        if (request.uri.path.endsWith('/refresh')) {
          refreshCalls++;
          return const WebBillingHttpResponse(
            200,
            '{"data":{"token":"new","refresh_token":"next"}}',
          );
        }
        if (request.headers['Authorization'] == 'Bearer expired') {
          expiredCalls++;
          if (expiredCalls == 2) await lateResponse.future;
          return const WebBillingHttpResponse(401, '{}');
        }
        return const WebBillingHttpResponse(200, '{"data":{"balance":5}}');
      },
    );

    final first = engine.execute(providerId: 'generic', config: config());
    final second = engine.execute(providerId: 'generic', config: config());
    final firstResult = await first;
    lateResponse.complete();
    final secondResult = await second;

    expect(firstResult.balance.value, 5);
    expect(secondResult.balance.value, 5);
    expect(refreshCalls, 1);
  });

  test('refresh outputs cannot write undeclared secure variables', () async {
    final invalid = WebBillingConfig(
      schemaVersion: 1,
      secretVariableDefinitions: const [access, refresh],
      requestTemplates: config().requestTemplates,
      metricRules: config().metricRules,
      credentialRefresh: CredentialRefreshConfig(
        requestTemplate: refreshConfig.requestTemplate,
        responseVariablePaths: const {'UNDECLARED': r'$.data.token'},
      ),
    );
    var writes = 0;
    final engine = WebBillingEngine(
      secretResolver: (_, name) async =>
          name == 'ACCESS_TOKEN' ? 'expired' : 'refresh',
      secretWriter: (_, values) async => writes++,
      transport: (request) async => request.uri.path.endsWith('/refresh')
          ? const WebBillingHttpResponse(200, '{"data":{"token":"new"}}')
          : const WebBillingHttpResponse(401, '{}'),
    );

    final result = await engine.execute(providerId: 'generic', config: invalid);

    expect(result.balance.failure, '账单认证刷新失败');
    expect(writes, 0);
  });

  test('concurrent 401 responses share one refresh operation', () async {
    final secrets = {'ACCESS_TOKEN': 'expired', 'REFRESH_TOKEN': 'refresh'};
    final refreshGate = Completer<void>();
    var refreshCalls = 0;
    final engine = WebBillingEngine(
      secretResolver: (_, name) async => secrets[name],
      secretWriter: (_, values) async => secrets.addAll(values),
      transport: (request) async {
        if (request.uri.path.endsWith('/refresh')) {
          refreshCalls++;
          await refreshGate.future;
          return const WebBillingHttpResponse(
            200,
            '{"data":{"token":"new","refresh_token":"next"}}',
          );
        }
        if (request.headers['Authorization'] == 'Bearer expired') {
          return const WebBillingHttpResponse(401, '{}');
        }
        return const WebBillingHttpResponse(200, '{"data":{"balance":5}}');
      },
    );

    final first = engine.execute(providerId: 'generic', config: config());
    final second = engine.execute(providerId: 'generic', config: config());
    await Future<void>.delayed(Duration.zero);
    refreshGate.complete();
    final results = await Future.wait([first, second]);

    expect(refreshCalls, 1);
    expect(results.map((item) => item.balance.value), everyElement(5));
  });
}
