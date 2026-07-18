import 'dart:convert';

import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/web_billing_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'generic GET resolves generic secure and system variables then parses scalar',
    () async {
      final sent = <RawHttpRequest>[];
      final engine = WebBillingEngine(
        secretResolver: (_, variable) async =>
            variable == 'AUTH_TOKEN' ? 'secure-token' : null,
        transport: (request) async {
          sent.add(request);
          return const WebBillingHttpResponse(
            200,
            '{"data":{"balance":"12.5"}}',
          );
        },
      );

      final result = await engine.execute(
        providerId: 'generic',
        config: _config(
          requestTemplates: const [
            RequestTemplate(
              id: 'balance',
              method: 'GET',
              urlTemplate: 'https://example.test/balance',
              queryTemplate: {'start': r'${DAY_START_UNIX}'},
              headersTemplate: {'Authorization': r'Bearer ${AUTH_TOKEN}'},
            ),
          ],
          metricRules: [
            _metric(WebBillingMetricKind.balance, 'balance', 'data.balance'),
          ],
        ),
        now: DateTime.utc(2026, 7, 13, 15, 30),
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.uri.queryParameters['start'], isNotNull);
      expect(sent.single.headers['Authorization'], 'Bearer secure-token');
      expect(result.balance.value, 12.5);
    },
  );

  test('generic POST sums values and applies scale', () async {
    final sent = <RawHttpRequest>[];
    final result =
        await WebBillingEngine(
          secretResolver: (_, _) async => 'secure-token',
          transport: (request) async {
            sent.add(request);
            return const WebBillingHttpResponse(
              200,
              '{"rows":[{"cost":"2"},{"cost":3}]}',
            );
          },
        ).execute(
          providerId: 'generic',
          config: _config(
            requestTemplates: const [
              RequestTemplate(
                id: 'daily',
                method: 'POST',
                urlTemplate: 'https://example.test/usage',
                bodyTemplate: r'{"from":"${MONTH_START_UNIX_MS}"}',
              ),
            ],
            metricRules: [
              MetricRule(
                id: 'daily',
                kind: WebBillingMetricKind.daily,
                requestTemplateId: 'daily',
                responseRule: const ResponseRule(
                  scalarPath: 'cost',
                  itemPath: 'rows[*]',
                  aggregation: ResponseAggregation.sum,
                ),
                multiplier: 2,
                divisor: 10,
              ),
            ],
          ),
        );

    expect(sent.single.method, 'POST');
    expect(jsonDecode(sent.single.body!), contains('from'));
    expect(result.daily.value, 1);
  });

  test(
    'missing required generic secret is safe and transport is not invoked',
    () async {
      var invoked = false;
      final result =
          await WebBillingEngine(
            secretResolver: (_, _) async => null,
            transport: (_) async {
              invoked = true;
              return const WebBillingHttpResponse(200, '{}');
            },
          ).execute(
            providerId: 'generic',
            config: _config(
              requestTemplates: const [
                RequestTemplate(
                  id: 'balance',
                  method: 'GET',
                  urlTemplate: 'https://example.test/',
                ),
              ],
              metricRules: [
                _metric(WebBillingMetricKind.balance, 'balance', 'value'),
              ],
            ),
          );

      expect(invoked, isFalse);
      expect(result.balance.failure, '未配置账单变量：访问令牌');
    },
  );

  test(
    'processing expression takes precedence over legacy response rule',
    () async {
      final result =
          await WebBillingEngine(
            secretResolver: (_, _) async => 'secure-token',
            transport: (_) async => const WebBillingHttpResponse(
              200,
              '{"data":{"items":[{"cost":20},{"cost":"30"}]},"legacy":999}',
            ),
          ).execute(
            providerId: 'generic',
            config: _config(
              requestTemplates: const [
                RequestTemplate(
                  id: 'balance',
                  method: 'GET',
                  urlTemplate: 'https://example.test/',
                ),
              ],
              metricRules: [
                MetricRule(
                  id: 'balance',
                  kind: WebBillingMetricKind.balance,
                  requestTemplateId: 'balance',
                  responseRule: const ResponseRule(scalarPath: 'legacy'),
                  multiplier: 10,
                  processingExpression: 'sum(data.items[*].cost) / 10',
                ),
              ],
            ),
          );

      expect(result.balance.value, 5);
    },
  );

  test(
    'expanded system variables resolve deterministically in templates',
    () async {
      final sent = <RawHttpRequest>[];
      await WebBillingEngine(
        secretResolver: (_, _) async => 'secure-token',
        transport: (request) async {
          sent.add(request);
          return const WebBillingHttpResponse(200, '{"value":1}');
        },
      ).execute(
        providerId: 'generic',
        config: _config(
          requestTemplates: const [
            RequestTemplate(
              id: 'balance',
              method: 'GET',
              urlTemplate: 'https://example.test/',
              queryTemplate: {
                'year': r'${CURRENT_YEAR}',
                'month': r'${CURRENT_MONTH}',
                'day': r'${CURRENT_DAY}',
                'date': r'${CURRENT_DATE}',
                'month_start': r'${MONTH_START_DATE}',
                'utc_date': r'${UTC_CURRENT_DATE}',
              },
            ),
          ],
          metricRules: [
            _metric(WebBillingMetricKind.balance, 'balance', 'value'),
          ],
        ),
        now: DateTime.utc(2026, 7, 13, 15, 30),
      );

      expect(sent.single.uri.queryParameters, {
        'year': '2026',
        'month': '7',
        'day': '13',
        'date': '2026-07-13',
        'month_start': '2026-07-01',
        'utc_date': '2026-07-13',
      });
    },
  );

  test(
    'invalid processing expressions return only the fixed safe failure',
    () async {
      for (final expression in ['unknown(data.value)', 'data.value / 0']) {
        final result =
            await WebBillingEngine(
              secretResolver: (_, _) async => 'secure-token',
              transport: (_) async => const WebBillingHttpResponse(
                200,
                '{"data":{"value":"private-value"}}',
              ),
            ).execute(
              providerId: 'generic',
              config: _config(
                requestTemplates: const [
                  RequestTemplate(
                    id: 'balance',
                    method: 'GET',
                    urlTemplate: 'https://example.test/',
                  ),
                ],
                metricRules: [
                  MetricRule(
                    id: 'balance',
                    kind: WebBillingMetricKind.balance,
                    requestTemplateId: 'balance',
                    responseRule: const ResponseRule(scalarPath: 'legacy'),
                    processingExpression: expression,
                  ),
                ],
              ),
            );

        expect(result.balance.failure, '账单数据处理表达式无效');
        expect(result.balance.failure, isNot(contains('private-value')));
        expect(result.balance.failure, isNot(contains(expression)));
      }
    },
  );

  test('HTTP and response failures are generic safe metric results', () async {
    final result =
        await WebBillingEngine(
          secretResolver: (_, _) async => 'secure-token',
          transport: (_) async =>
              const WebBillingHttpResponse(500, 'private response'),
        ).execute(
          providerId: 'generic',
          config: _config(
            requestTemplates: const [
              RequestTemplate(
                id: 'balance',
                method: 'GET',
                urlTemplate: 'https://example.test/',
              ),
            ],
            metricRules: [
              _metric(WebBillingMetricKind.balance, 'balance', 'value'),
            ],
          ),
        );
    expect(result.balance.failure, '账单请求 HTTP 500');
  });
}

const _secret = SecretVariableDefinition(
  id: 'auth',
  name: 'AUTH_TOKEN',
  displayName: '访问令牌',
  type: SecretVariableType.bearerToken,
  required: true,
);

WebBillingConfig _config({
  required List<RequestTemplate> requestTemplates,
  required List<MetricRule> metricRules,
  List<SecretVariableDefinition> secretVariables = const [_secret],
}) => WebBillingConfig(
  schemaVersion: 1,
  requestTemplates: requestTemplates,
  metricRules: metricRules,
  secretVariableDefinitions: secretVariables,
);

MetricRule _metric(WebBillingMetricKind kind, String requestId, String path) =>
    MetricRule(
      id: kind.name,
      kind: kind,
      requestTemplateId: requestId,
      responseRule: ResponseRule(scalarPath: path),
    );
