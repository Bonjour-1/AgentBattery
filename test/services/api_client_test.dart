import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/web_billing_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('no executable generic billing config throws a safe error', () async {
    final api = ApiClient();
    addTearDown(api.close);

    await expectLater(
      api.fetchMetrics(_provider()),
      throwsA(
        isA<ApiException>()
            .having((error) => error.message, 'message', '未配置网页账单请求')
            .having((error) => error.safeCategory, 'category', 'web-billing'),
      ),
    );
  });

  test('legacy advanced fields cannot make fetchMetrics executable', () async {
    var requests = 0;
    final api = ApiClient(
      webBillingEngine: WebBillingEngine(
        transport: (_) async {
          requests++;
          return const WebBillingHttpResponse(200, '{"value":99}');
        },
      ),
    );
    addTearDown(api.close);
    final legacyOnly = _provider().copyWith(
      advancedEnabled: true,
      balanceUrl: 'https://legacy.invalid/private',
      balanceBody: 'secret body',
      balanceHeaders: '{"Authorization":"secret"}',
      balanceJsonPath: 'legacy.value',
    );

    await expectLater(
      api.fetchMetrics(legacyOnly),
      throwsA(
        isA<ApiException>()
            .having((error) => error.message, 'message', '未配置网页账单请求')
            .having((error) => error.safeCategory, 'category', 'web-billing'),
      ),
    );
    expect(requests, 0);
  });

  test('generic balance, daily and monthly rules use one engine', () async {
    final sent = <RawHttpRequest>[];
    final api = ApiClient(
      webBillingEngine: WebBillingEngine(
        secretResolver: (_, variable) async =>
            variable == 'TOKEN' ? 'generic-secret' : null,
        transport: (request) async {
          sent.add(request);
          return WebBillingHttpResponse(200, switch (request.uri.path) {
            '/balance' => '{"value":12.5}',
            '/daily' => '{"value":2}',
            _ => '{"value":8}',
          });
        },
      ),
    );
    addTearDown(api.close);

    final result = await api.fetchMetrics(
      _provider(webBillingConfig: _config()),
    );

    expect(result.balance, 12.5);
    expect(result.dailyUsage, 2);
    expect(result.monthlyUsage, 8);
    expect(result.dailyRequested, isTrue);
    expect(result.monthlyRequested, isTrue);
    expect(result.dailySucceeded, isTrue);
    expect(result.monthlySucceeded, isTrue);
    expect(sent.map((request) => request.uri.path), [
      '/balance',
      '/daily',
      '/monthly',
    ]);
  });

  test(
    'fetchBalance forwards to generic billing, never legacy fields',
    () async {
      final api = ApiClient(
        webBillingEngine: WebBillingEngine(
          transport: (_) async =>
              const WebBillingHttpResponse(200, '{"value":7}'),
        ),
      );
      addTearDown(api.close);
      final config = _provider(webBillingConfig: _balanceOnlyConfig()).copyWith(
        advancedEnabled: true,
        balanceUrl: 'https://legacy.invalid/private',
        balanceBody: 'secret body',
        balanceHeaders: '{"Authorization":"secret"}',
        balanceJsonPath: 'legacy.value',
      );

      final result = await api.fetchBalance(config);

      expect(result.balance, 7);
    },
  );

  test('balance failure throws only a safe classified error', () async {
    const secret = 'must-not-leak';
    final api = ApiClient(
      webBillingEngine: WebBillingEngine(
        secretResolver: (_, _) async => secret,
        transport: (_) async =>
            const WebBillingHttpResponse(500, 'response: must-not-leak'),
      ),
    );
    addTearDown(api.close);

    await expectLater(
      api.fetchMetrics(_provider(webBillingConfig: _config())),
      throwsA(
        isA<ApiException>()
            .having((error) => error.message, 'message', '账单请求 HTTP 500')
            .having((error) => error.safeCategory, 'category', 'web-billing')
            .having(
              (error) => error.message.contains(secret),
              'secret leaked',
              isFalse,
            ),
      ),
    );
  });

  test(
    'validate remains a model API request authenticated by apiKey',
    () async {
      late http.Request request;
      final client = MockClient((value) async {
        request = value;
        return http.Response('[]', 200);
      });
      final api = ApiClient(client: client);
      addTearDown(api.close);

      await api.validate(_provider(apiKey: 'model-api-key'));

      expect(request.url.toString(), 'https://api.example.test/v1/models');
      expect(request.headers['authorization'], 'Bearer model-api-key');
    },
  );
}

ProviderConfig _provider({
  String apiKey = '',
  WebBillingConfig? webBillingConfig,
}) => ProviderConfig(
  id: 'generic',
  name: 'Generic',
  colorValue: 0,
  order: 0,
  enabled: true,
  baseUrl: 'https://api.example.test/v1',
  apiKey: apiKey,
  webBillingConfig: webBillingConfig,
);

WebBillingConfig _balanceOnlyConfig() => WebBillingConfig(
  schemaVersion: 1,
  requestTemplates: const [
    RequestTemplate(
      id: 'balance',
      method: 'GET',
      urlTemplate: 'https://billing.test/balance',
    ),
  ],
  metricRules: [_metric(WebBillingMetricKind.balance)],
);

WebBillingConfig _config() => WebBillingConfig(
  schemaVersion: 1,
  secretVariableDefinitions: const [
    SecretVariableDefinition(
      id: 'token',
      name: 'TOKEN',
      displayName: '令牌',
      type: SecretVariableType.bearerToken,
      required: true,
    ),
  ],
  requestTemplates: const [
    RequestTemplate(
      id: 'balance',
      method: 'GET',
      urlTemplate: 'https://billing.test/balance',
      headersTemplate: {'Authorization': r'Bearer ${TOKEN}'},
    ),
    RequestTemplate(
      id: 'daily',
      method: 'GET',
      urlTemplate: 'https://billing.test/daily',
      headersTemplate: {'Authorization': r'Bearer ${TOKEN}'},
    ),
    RequestTemplate(
      id: 'monthly',
      method: 'GET',
      urlTemplate: 'https://billing.test/monthly',
      headersTemplate: {'Authorization': r'Bearer ${TOKEN}'},
    ),
  ],
  metricRules: [for (final kind in WebBillingMetricKind.values) _metric(kind)],
);

MetricRule _metric(WebBillingMetricKind kind) => MetricRule(
  id: kind.name,
  kind: kind,
  requestTemplateId: kind.name,
  responseRule: const ResponseRule(scalarPath: 'value'),
);
