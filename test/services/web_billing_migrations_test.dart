import 'dart:convert';

import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/web_billing_engine.dart';
import 'package:agent_battery_flutter/services/web_billing_migrations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const safeValue = 'test-value';
  const mockSecretValues = [
    'deepseek-api-key-for-test',
    'deepseek-web-bearer-for-test',
    'siliconflow-cookie-for-test',
    'siliconflow-subject-id-for-test',
    'codeapi-web-bearer-for-test',
  ];

  test('migration factories serialize templates and secret metadata only', () {
    final configs = [
      deepSeekWebBillingConfig(),
      siliconFlowWebBillingConfig(),
      codeApiWebBillingConfig(),
    ];
    final serialized = jsonEncode(
      configs.map((config) => config.toJson()).toList(),
    );

    for (final secretValue in mockSecretValues) {
      expect(serialized, isNot(contains(secretValue)));
    }
    expect(deepSeekWebBillingConfig().source, 'legacy_deepseek');
    expect(
      deepSeekWebBillingConfig().secretVariableDefinitions.map(
        (secret) => secret.name,
      ),
      containsAll(['DEEPSEEK_API_KEY', 'DEEPSEEK_WEB_BEARER']),
    );
    expect(
      siliconFlowWebBillingConfig().secretVariableDefinitions.map(
        (secret) => secret.type,
      ),
      containsAll([
        SecretVariableType.cookieHeader,
        SecretVariableType.subjectId,
      ]),
    );
    expect(
      codeApiWebBillingConfig().secretVariableDefinitions.single.name,
      'CODEAPI_WEB_BEARER',
    );
    expect(serialized, contains(r'${DEEPSEEK_API_KEY}'));
    expect(serialized, contains(r'${DEEPSEEK_WEB_BEARER}'));
    expect(serialized, contains(r'${COOKIE}'));
    expect(serialized, contains(r'${SUBJECT_ID}'));
    expect(serialized, contains(r'${CODEAPI_WEB_BEARER}'));
  });

  test(
    'DeepSeek factory resolves UTC web requests and parses all metrics',
    () async {
      final sent = <RawHttpRequest>[];
      final engine = WebBillingEngine(
        secretResolver: _resolver({
          'DEEPSEEK_API_KEY': safeValue,
          'DEEPSEEK_WEB_BEARER': safeValue,
        }),
        transport: (request) async {
          sent.add(request);
          return request.uri.path == '/user/balance'
              ? const WebBillingHttpResponse(
                  200,
                  '{"balance_infos":[{"total_balance":4}]}',
                )
              : const WebBillingHttpResponse(
                  200,
                  '{"data":{"biz_data":{"data":[{"series":[{"buckets":[{"cost":1.5},{"cost":2.5}]}]}]}}}',
                );
        },
      );

      final result = await engine.execute(
        providerId: 'deepseek',
        config: deepSeekWebBillingConfig(),
        now: DateTime.utc(2026, 7, 13, 12),
      );

      expect(result.balance.value, 4);
      expect(result.daily.value, 4);
      expect(result.monthly.value, 4);
      expect(sent[0].headers['Authorization'], 'Bearer $safeValue');
      expect(sent[1].uri.queryParameters['tz'], '0');
      expect(sent[1].uri.queryParameters['start'], '1783900800');
      expect(sent[1].uri.queryParameters['end'], '1783987200');
    },
  );

  test(
    'SiliconFlow factory resolves local millisecond requests and business rule',
    () async {
      final sent = <RawHttpRequest>[];
      final engine = WebBillingEngine(
        secretResolver: _resolver({
          'COOKIE': safeValue,
          'SUBJECT_ID': safeValue,
        }),
        transport: (request) async {
          sent.add(request);
          return request.uri.path.endsWith('/peek')
              ? const WebBillingHttpResponse(
                  200,
                  '{"code":20000,"data":{"financialInfo":{"balance":"3000000000000"}}}',
                )
              : const WebBillingHttpResponse(
                  200,
                  '{"code":20000,"data":{"netAmount":"2.5"}}',
                );
        },
      );

      final result = await engine.execute(
        providerId: 'siliconflow',
        config: siliconFlowWebBillingConfig(),
        now: DateTime.utc(2026, 7, 13, 12),
      );

      expect(result.balance.value, 3);
      expect(result.daily.value, 2.5);
      expect(result.monthly.value, 2.5);
      expect(sent[0].headers['Cookie'], safeValue);
      expect(sent[0].headers['x-subject-id'], safeValue);
      final localNow = DateTime.utc(2026, 7, 13, 12).toLocal();
      final localEnd = DateTime(
        localNow.year,
        localNow.month,
        localNow.day + 1,
      ).subtract(const Duration(milliseconds: 1));
      expect(
        sent[1].uri.queryParameters['endTime'],
        '${localEnd.toUtc().millisecondsSinceEpoch}',
      );
    },
  );

  test(
    'CodeAPI factory resolves bearer header and parses balance and daily only',
    () async {
      final sent = <RawHttpRequest>[];
      final result = await WebBillingEngine(
        secretResolver: _resolver({'CODEAPI_WEB_BEARER': safeValue}),
        transport: (request) async {
          sent.add(request);
          return const WebBillingHttpResponse(
            200,
            '{"balance_usd":8,"today_cost_usd":1.5}',
          );
        },
      ).execute(providerId: 'codeapi', config: codeApiWebBillingConfig());

      expect(result.balance.value, 8);
      expect(result.daily.value, 1.5);
      expect(result.monthly.requested, isFalse);
      expect(sent, hasLength(2));
      expect(sent.first.headers['Authorization'], 'Bearer $safeValue');
    },
  );

  test(
    'raw legacy snapshot attaches matching template and preserves existing or clean config',
    () {
      final deepSeek = const ProviderConfig(
        id: 'deepseek',
        name: 'DeepSeek',
        colorValue: 0,
        order: 0,
        enabled: true,
        baseUrl: 'https://api.deepseek.com/v1',
      );
      final rawLegacy = <String, Object?>{
        'advanced_enabled': true,
        'balance_url': 'https://api.deepseek.com/user/balance',
        'balance_json_path': 'balance_infos[0].total_balance',
        'daily_request': deepSeekDailyCostRequest.toJson(),
        'monthly_request': deepSeekMonthlyCostRequest.toJson(),
      };
      final snapshot = LegacyBillingSnapshot.fromJson(rawLegacy);
      final migrated = migrateLegacyProviderToWebBillingConfig(
        deepSeek,
        snapshot,
      );
      expect(migrated.webBillingConfig?.source, 'legacy_deepseek');

      final existing = codeApiWebBillingConfig();
      final preserved = migrateLegacyProviderToWebBillingConfig(
        deepSeek.copyWith(webBillingConfig: existing),
        snapshot,
      );
      expect(identical(preserved.webBillingConfig, existing), isTrue);

      final clean = const ProviderConfig(
        id: 'custom',
        name: 'Custom',
        colorValue: 0,
        order: 1,
        enabled: true,
        baseUrl: 'https://example.test/v1',
      );
      expect(
        identical(migrateLegacyProviderToWebBillingConfig(clean), clean),
        isTrue,
      );
    },
  );
}

WebBillingSecretResolver _resolver(Map<String, String> values) =>
    (_, variable) async => values[variable];
