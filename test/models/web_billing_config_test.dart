import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const request = RequestTemplate(
    id: 'daily-request',
    method: 'GET',
    urlTemplate:
        'https://billing.example.test/usage?start=${r'${LOCAL_DAY_START_MS}'}',
    queryTemplate: {'end': r'${LOCAL_DAY_END_MS}'},
    headersTemplate: {'Authorization': r'Bearer ${API_TOKEN}'},
    bodyTemplate: r'{"project":"${PROJECT_ID}"}',
    successRule: BusinessSuccessRule(
      jsonPath: r'$.code',
      operator: BusinessSuccessOperator.equals,
      expected: 0,
    ),
  );

  final genericConfig = WebBillingConfig(
    schemaVersion: 1,
    requestTemplates: [request],
    secretVariableDefinitions: [
      SecretVariableDefinition(
        id: 'api-token',
        name: 'API_TOKEN',
        displayName: 'Main API token',
        type: SecretVariableType.bearerToken,
        required: true,
      ),
    ],
    metricRules: [
      MetricRule(
        id: 'daily-cost',
        kind: WebBillingMetricKind.daily,
        requestTemplateId: 'daily-request',
        responseRule: ResponseRule(
          scalarPath: r'$.data.cost',
          itemPath: r'$.data.items[*].cost',
          aggregation: ResponseAggregation.sum,
        ),
        multiplier: 100,
        divisor: 1000,
        processingExpression: 'sum(data.items[*].cost) / 1000',
        unit: '元',
      ),
    ],
    displayPolicy: DisplayPolicy(
      balance: MetricFailureDisplay.showCached,
      daily: MetricFailureDisplay.estimateFallback,
      monthly: MetricFailureDisplay.hide,
    ),
    source: 'local',
    migrationMetadata: {'legacy_id': 'old-provider'},
  );

  test(
    'all generic web billing models JSON round trip without changing templates',
    () {
      final restored = WebBillingConfig.fromJson(genericConfig.toJson());

      expect(restored.toJson(), genericConfig.toJson());
      expect(
        restored.requestTemplates.single.urlTemplate,
        contains(r'${LOCAL_DAY_START_MS}'),
      );
      expect(
        restored.requestTemplates.single.headersTemplate['Authorization'],
        r'Bearer ${API_TOKEN}',
      );
      expect(
        restored.requestTemplates.single.bodyTemplate,
        r'{"project":"${PROJECT_ID}"}',
      );
    },
  );

  test(
    'secret variable definitions contain metadata only and never serialize values',
    () {
      const definition = SecretVariableDefinition(
        id: 'cookie',
        name: 'BILLING_COOKIE',
        displayName: 'Billing cookie',
        type: SecretVariableType.cookieHeader,
        required: true,
      );

      expect(definition.toJson().containsKey('value'), isFalse);
      expect(definition.toJson().containsValue('secret-cookie-value'), isFalse);
    },
  );

  test('invalid metric multiplier and divisor safely default to one', () {
    final rule = MetricRule.fromJson({
      'id': 'invalid-scale',
      'kind': 'balance',
      'request_template_id': 'request',
      'response_rule': {'scalar_path': r'$.data.balance'},
      'multiplier': 0,
      'divisor': -2,
    });

    expect(rule.multiplier, 1);
    expect(rule.divisor, 1);
  });

  test('display policy JSON round trips', () {
    const policy = DisplayPolicy(
      balance: MetricFailureDisplay.showCached,
      daily: MetricFailureDisplay.estimateFallback,
      monthly: MetricFailureDisplay.hide,
    );

    expect(DisplayPolicy.fromJson(policy.toJson()).toJson(), policy.toJson());
  });
}
