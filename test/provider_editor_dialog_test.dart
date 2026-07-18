import 'dart:convert';

import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:agent_battery_flutter/ui/screens/provider_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureKeyStore implements SecureKeyStore {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _secret = 'curl-bearer-secret-must-not-appear';
const _curl =
    "curl 'https://billing.example.test/usage' -H 'Authorization: Bearer $_secret' -H 'Accept: application/json'";

void main() {
  Future<BatteryController> pumpEditor(
    WidgetTester tester, {
    ProviderConfig? initial,
    StorageService? storage,
  }) async {
    final controller = BatteryController(
      storage: storage ?? StorageService(keyStore: _MemorySecureKeyStore()),
      api: ApiClient(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProviderEditorDialog(controller: controller, initial: initial),
        ),
      ),
    );
    return controller;
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  Finder apiKeyValue() => find.descendant(
    of: find.byKey(const ValueKey('variable-api_key-API_KEY')),
    matching: field('安全变量值'),
  );
  Finder deleteVariable(String id) =>
      find.byKey(ValueKey('delete-variable-$id'));

  Future<void> enterVisibleText(
    WidgetTester tester,
    Finder finder,
    String text,
  ) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  String metricLabel(WebBillingMetricKind kind) => switch (kind) {
    WebBillingMetricKind.balance => '余额 Balance',
    WebBillingMetricKind.daily => '今日 Today',
    WebBillingMetricKind.monthly => '本月 Month',
  };

  Finder curlSource(WebBillingMetricKind kind) =>
      find.byKey(ValueKey('curl-source-${kind.name}'));
  Finder parseCurl(WebBillingMetricKind kind) =>
      find.byKey(ValueKey('parse-curl-${kind.name}'));
  Finder applyCurl(WebBillingMetricKind kind) =>
      find.byKey(ValueKey('apply-curl-${kind.name}'));
  Finder failureDisplay(WebBillingMetricKind kind) =>
      find.byKey(ValueKey('metric-failure-display-${kind.name}'));

  Future<void> importCurl(
    WidgetTester tester, [
    WebBillingMetricKind kind = WebBillingMetricKind.balance,
  ]) async {
    await enterVisibleText(tester, curlSource(kind), _curl);
    await tapVisible(tester, parseCurl(kind));
    await tester.pump();
  }

  testWidgets(
    'three-section generic billing UI exposes an independent cURL parse and apply flow per metric',
    (tester) async {
      final controller = await pumpEditor(
        tester,
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
        ),
      );
      addTearDown(controller.dispose);

      expect(find.textContaining('DeepSeek'), findsNothing);
      expect(find.textContaining('SiliconFlow'), findsNothing);
      expect(find.textContaining('CodeAPI'), findsNothing);
      expect(find.text('高级账单设置'), findsNothing);
      expect(find.text('GET 请求通常无需 JSON 请求体'), findsNothing);

      expect(find.text('基本服务商设置'), findsOneWidget);
      expect(field('显示名称'), findsOneWidget);
      expect(field('OpenAI Base URL（自动规范化为 /v1）'), findsOneWidget);
      expect(field('默认模型（可选）'), findsOneWidget);
      expect(field('API Key'), findsNothing);
      expect(
        find.byKey(const ValueKey('variable-api_key-API_KEY')),
        findsOneWidget,
      );
      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('变量名：API_KEY'), findsOneWidget);
      expect(find.text(r'请求中请使用 ${API_KEY}。API Key 只是显示名称。'), findsOneWidget);
      expect(find.text('通用网页账单'), findsOneWidget);
      for (final kind in WebBillingMetricKind.values) {
        expect(find.text(metricLabel(kind)), findsOneWidget);
        expect(curlSource(kind), findsOneWidget);
        expect(parseCurl(kind), findsOneWidget);
        expect(applyCurl(kind), findsNothing);
      }

      for (final kind in WebBillingMetricKind.values) {
        await importCurl(tester, kind);
        expect(
          find.textContaining('安全预览：GET https://billing.example.test/usage'),
          findsNWidgets(kind.index + 1),
        );
        expect(applyCurl(kind), findsOneWidget);
      }
      expect(field('变量显示名称'), findsOneWidget);
      expect(field('变量名（A-Z、0-9、_）'), findsOneWidget);
      expect(find.text(_secret), findsNothing);

      for (final kind in WebBillingMetricKind.values) {
        await tapVisible(tester, applyCurl(kind));
        await tester.pump();
      }
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.controller?.text == 'https://billing.example.test/usage',
        ),
        findsNWidgets(WebBillingMetricKind.values.length),
      );
      expect(
        curlSource(WebBillingMetricKind.balance).evaluate().single.widget,
        isA<TextField>(),
      );
      final source =
          curlSource(WebBillingMetricKind.balance).evaluate().single.widget
              as TextField;
      expect(source.controller!.text, isEmpty);
    },
  );

  testWidgets(
    'data processing editor replaces legacy controls and persists safe expression',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = await pumpEditor(
        tester,
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
        ),
      );
      addTearDown(controller.dispose);

      await importCurl(tester);
      await tapVisible(tester, applyCurl(WebBillingMetricKind.balance));
      await tester.pump();
      expect(field('数据处理'), findsOneWidget);
      expect(field('JSON 标量路径'), findsNothing);
      expect(field('JSON 项目路径'), findsNothing);
      expect(field('乘数'), findsNothing);
      expect(field('除数'), findsNothing);
      expect(find.text('汇总方式'), findsNothing);
      expect(find.text('表达式的最终数值即显示结果。'), findsOneWidget);
      expect(find.text('可用时间变量'), findsOneWidget);
      expect(failureDisplay(WebBillingMetricKind.balance), findsOneWidget);
      await tapVisible(tester, find.text('可用时间变量'));
      await tester.pumpAndSettle();
      expect(find.text(r'${CURRENT_DATE}'), findsOneWidget);
      expect(find.text(r'${MONTH_START_DATE}'), findsOneWidget);
      expect(find.text(r'${DAY_START_UNIX}'), findsOneWidget);

      await enterVisibleText(tester, field('数据处理'), 'data.amount * 100 / 10');
      await tapVisible(tester, failureDisplay(WebBillingMetricKind.balance));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('显示缓存值'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();

      expect(
        controller.configs,
        isNotEmpty,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data)
            .whereType<String>()
            .join(' | '),
      );
      final web = controller.configs.single.webBillingConfig!;
      final rule = web.metricRules.single;
      expect(rule.processingExpression, 'data.amount * 100 / 10');
      expect(rule.responseRule.scalarPath, isEmpty);
      expect(web.displayPolicy.balance, MetricFailureDisplay.showCached);
    },
  );

  testWidgets(
    'secret is masked, stored by generic variable only, and excluded from config JSON',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final keys = _MemorySecureKeyStore();
      final controller = await pumpEditor(
        tester,
        storage: StorageService(keyStore: keys),
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
        ),
      );
      addTearDown(controller.dispose);

      await importCurl(tester);
      expect(find.text(_secret), findsNothing);
      expect(
        find.textContaining('安全预览：GET https://billing.example.test/usage'),
        findsOneWidget,
      );
      await enterVisibleText(tester, field('安全变量值').last, _secret);
      await tapVisible(tester, applyCurl(WebBillingMetricKind.balance));
      await tester.pump();
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();

      final saved = controller.configs.single;
      final preferences = await SharedPreferences.getInstance();
      final persisted = preferences.getString('agent_battery_state_v1')!;
      expect(saved.toJson().toString(), isNot(contains(_secret)));
      expect(
        saved.webBillingConfig!.toJson().toString(),
        isNot(contains(_secret)),
      );
      expect(jsonDecode(persisted).toString(), isNot(contains(_secret)));
      expect(
        keys.values[ProviderKeyManager.webBillingVariableKeyFor(
          'provider-a',
          'AUTHORIZATION_TOKEN',
        )],
        _secret,
      );
      expect(keys.values.keys.join(), isNot(contains('deepseek')));
    },
  );

  testWidgets(
    'cURL apply queues parsed secret candidates for secure save without widget plaintext',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final keys = _MemorySecureKeyStore();
      final controller = await pumpEditor(
        tester,
        storage: StorageService(keyStore: keys),
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
        ),
      );
      addTearDown(controller.dispose);

      await importCurl(tester);
      expect(find.text(_secret), findsNothing);
      await tapVisible(tester, applyCurl(WebBillingMetricKind.balance));
      await tester.pump();
      expect(
        (field('安全变量值').last.evaluate().single.widget as TextField)
            .controller!
            .text,
        isNot(_secret),
      );
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();

      expect(
        keys.values[ProviderKeyManager.webBillingVariableKeyFor(
          'provider-a',
          'AUTHORIZATION_TOKEN',
        )],
        _secret,
      );
      final persisted = (await SharedPreferences.getInstance()).getString(
        'agent_battery_state_v1',
      )!;
      expect(persisted, isNot(contains(_secret)));
    },
  );

  testWidgets('generic variable name validation blocks save', (tester) async {
    final controller = await pumpEditor(
      tester,
      initial: const ProviderConfig(
        id: 'provider-a',
        name: 'Provider A',
        colorValue: 0,
        order: 0,
        enabled: true,
        baseUrl: 'https://example.test/v1',
      ),
    );
    addTearDown(controller.dispose);

    await tapVisible(tester, find.text('添加安全变量'));
    await tester.pump();
    await enterVisibleText(tester, field('变量名（A-Z、0-9、_）'), 'not-valid');
    await tapVisible(tester, find.text('保存'));
    await tester.pump();
    expect(find.text('变量名必须符合 [A-Z][A-Z0-9_]* 且在配置内唯一'), findsOneWidget);
  });

  testWidgets(
    'metric and variable editors retain successive text after rebuilds',
    (tester) async {
      final request = RequestTemplate(
        id: 'request',
        method: 'GET',
        urlTemplate: 'https://billing.example.test/usage',
      );
      final controller = await pumpEditor(
        tester,
        initial: ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
          webBillingConfig: WebBillingConfig(
            schemaVersion: 1,
            requestTemplates: [request],
            secretVariableDefinitions: const [
              SecretVariableDefinition(
                id: 'token',
                name: 'TOKEN',
                displayName: 'Token',
                type: SecretVariableType.genericHeaderValue,
                required: true,
              ),
            ],
            metricRules: [
              MetricRule(
                id: 'balance',
                kind: WebBillingMetricKind.balance,
                requestTemplateId: request.id,
                responseRule: const ResponseRule(scalarPath: ''),
              ),
            ],
          ),
        ),
      );
      addTearDown(controller.dispose);

      final processing = find.byKey(
        const ValueKey('metric-processing-balance'),
      );
      await enterVisibleText(tester, processing, 'd');
      await tester.pump();
      await enterVisibleText(tester, processing, 'data.balance');
      await tester.pump();
      expect(
        (processing.evaluate().single.widget as TextField).controller!.text,
        'data.balance',
      );

      final displayName = field('变量显示名称');
      final variableName = field('变量名（A-Z、0-9、_）');
      await enterVisibleText(tester, displayName, 'T');
      await tester.pump();
      await enterVisibleText(tester, displayName, 'Token name');
      await tester.pump();
      await enterVisibleText(tester, variableName, 'T');
      await tester.pump();
      await enterVisibleText(tester, variableName, 'TOKEN_VALUE');
      await tester.pump();
      expect(
        (displayName.evaluate().single.widget as TextField).controller!.text,
        'Token name',
      );
      expect(
        (variableName.evaluate().single.widget as TextField).controller!.text,
        'TOKEN_VALUE',
      );
    },
  );

  testWidgets(
    'daily import replaces only daily metric and preserves other rules',
    (tester) async {
      final old = RequestTemplate(
        id: 'old',
        method: 'GET',
        urlTemplate: 'https://old.test',
      );
      final initial = ProviderConfig(
        id: 'provider-a',
        name: 'Provider A',
        colorValue: 0,
        order: 0,
        enabled: true,
        baseUrl: 'https://example.test/v1',
        webBillingConfig: WebBillingConfig(
          schemaVersion: 1,
          requestTemplates: [old],
          metricRules: [
            MetricRule(
              id: 'balance',
              kind: WebBillingMetricKind.balance,
              requestTemplateId: 'old',
              responseRule: const ResponseRule(scalarPath: 'balance'),
            ),
            MetricRule(
              id: 'daily',
              kind: WebBillingMetricKind.daily,
              requestTemplateId: 'old',
              responseRule: const ResponseRule(scalarPath: 'daily'),
            ),
            MetricRule(
              id: 'monthly',
              kind: WebBillingMetricKind.monthly,
              requestTemplateId: 'old',
              responseRule: const ResponseRule(scalarPath: 'month'),
            ),
          ],
        ),
      );
      final controller = await pumpEditor(tester, initial: initial);
      addTearDown(controller.dispose);
      await importCurl(tester, WebBillingMetricKind.daily);
      await tapVisible(tester, applyCurl(WebBillingMetricKind.daily));
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();
      final rules = controller.configs.single.webBillingConfig!.metricRules;
      expect(
        rules
            .firstWhere((rule) => rule.kind == WebBillingMetricKind.daily)
            .responseRule
            .scalarPath,
        isEmpty,
      );
      expect(
        rules
            .firstWhere((rule) => rule.kind == WebBillingMetricKind.balance)
            .responseRule
            .scalarPath,
        'balance',
      );
      expect(
        rules
            .firstWhere((rule) => rule.kind == WebBillingMetricKind.monthly)
            .responseRule
            .scalarPath,
        'month',
      );
    },
  );

  testWidgets(
    'manual secure variable saves metadata and secret only to generic secure store',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final keys = _MemorySecureKeyStore();
      final controller = await pumpEditor(
        tester,
        storage: StorageService(keyStore: keys),
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
        ),
      );
      addTearDown(controller.dispose);
      await tapVisible(tester, find.text('添加安全变量'));
      await tester.pump();
      await enterVisibleText(tester, field('变量显示名称'), '手动令牌');
      await enterVisibleText(tester, field('变量名（A-Z、0-9、_）'), 'MANUAL_TOKEN');
      await enterVisibleText(tester, field('安全变量值').last, _secret);
      expect(
        (field('安全变量值').evaluate().last.widget as TextField).obscureText,
        isTrue,
      );
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();
      final saved = controller.configs.single.webBillingConfig!;
      final manualVariable = saved.secretVariableDefinitions.firstWhere(
        (variable) => variable.name == 'MANUAL_TOKEN',
      );
      expect(manualVariable.displayName, '手动令牌');
      expect(saved.toJson().toString(), isNot(contains(_secret)));
      expect(
        keys.values[ProviderKeyManager.webBillingVariableKeyFor(
          'provider-a',
          'MANUAL_TOKEN',
        )],
        _secret,
      );
    },
  );

  testWidgets('manual secure variable can be deleted', (tester) async {
    final controller = await pumpEditor(
      tester,
      initial: _providerWithManualVariable(),
    );
    addTearDown(controller.dispose);

    expect(deleteVariable('manual-token'), findsOneWidget);
    await tapVisible(tester, deleteVariable('manual-token'));
    await tester.pump();
    expect(deleteVariable('manual-token'), findsNothing);
    await tapVisible(tester, find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      controller.configs.single.webBillingConfig!.secretVariableDefinitions
          .where((variable) => variable.name == 'MANUAL_TOKEN'),
      isEmpty,
    );
  });

  testWidgets('API_KEY variable has no delete control', (tester) async {
    final controller = await pumpEditor(tester);
    addTearDown(controller.dispose);

    expect(deleteVariable('api_key'), findsNothing);
  });

  testWidgets('malformed request placeholder blocks save safely', (
    tester,
  ) async {
    final controller = await pumpEditor(
      tester,
      initial: _providerWithRequest(
        'https://billing.example.test/?key=\${API KEY}',
      ),
    );
    addTearDown(controller.dispose);

    await tapVisible(tester, find.text('保存'));
    await tester.pump();
    expect(
      find.text(r'请求占位符变量名只能包含字母、数字和下划线；模型 API Key 请使用 ${API_KEY}'),
      findsOneWidget,
    );
  });

  testWidgets('undefined request placeholder blocks save safely', (
    tester,
  ) async {
    final controller = await pumpEditor(
      tester,
      initial: _providerWithRequest(
        'https://billing.example.test/?key=\${KEY}',
      ),
    );
    addTearDown(controller.dispose);

    await tapVisible(tester, find.text('保存'));
    await tester.pump();
    expect(find.text('未定义请求变量：KEY'), findsOneWidget);
  });

  testWidgets('API_KEY request placeholder saves without a duplicate secret', (
    tester,
  ) async {
    final controller = await pumpEditor(
      tester,
      initial: _providerWithRequest(
        'https://billing.example.test/?key=\${API_KEY}',
      ),
    );
    addTearDown(controller.dispose);

    await tapVisible(tester, find.text('保存'));
    await tester.pumpAndSettle();
    expect(controller.configs, hasLength(1));
    expect(
      controller
          .configs
          .single
          .webBillingConfig!
          .requestTemplates
          .single
          .urlTemplate,
      r'https://billing.example.test/?key=${API_KEY}',
    );
  });

  testWidgets('deleting a referenced secure variable is blocked safely', (
    tester,
  ) async {
    final request = RequestTemplate(
      id: 'balance-request',
      method: 'GET',
      urlTemplate: 'https://billing.example.test/?token=\${MANUAL_TOKEN}',
    );
    final controller = await pumpEditor(
      tester,
      initial: _providerWithManualVariable(request: request),
    );
    addTearDown(controller.dispose);

    await tapVisible(tester, deleteVariable('manual-token'));
    await tester.pump();
    expect(find.text('无法删除安全变量 MANUAL_TOKEN：它仍被请求模板使用。'), findsOneWidget);
    expect(deleteVariable('manual-token'), findsOneWidget);
  });

  testWidgets(
    'request template editors persist all imported daily request fields',
    (tester) async {
      final controller = await pumpEditor(
        tester,
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
        ),
      );
      addTearDown(controller.dispose);

      await importCurl(tester, WebBillingMetricKind.daily);
      await tapVisible(tester, applyCurl(WebBillingMetricKind.daily));
      await tester.pump();

      final method = field('请求方法');
      final url = field('URL 模板');
      final query = field('Query 参数模板（JSON）');
      final headers = field('Headers 模板（JSON）');
      final body = field('Body 模板');
      expect(method, findsOneWidget);
      expect(url, findsOneWidget);
      expect(query, findsOneWidget);
      expect(headers, findsOneWidget);
      expect(body, findsOneWidget);

      await enterVisibleText(tester, url, 'https://billing.example.test/d');
      await tester.pump();
      await enterVisibleText(tester, url, 'https://billing.example.test/daily');
      await tester.pump();
      expect(
        (url.evaluate().single.widget as TextField).controller!.text,
        'https://billing.example.test/daily',
      );
      await enterVisibleText(tester, method, 'POST');
      await enterVisibleText(tester, query, '{"date":"today"}');
      await enterVisibleText(tester, headers, '{"X-Test":"\${API_KEY}"}');
      await enterVisibleText(tester, body, '{"metric":"daily"}');
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();

      final web = controller.configs.single.webBillingConfig!;
      final daily = web.metricRules.firstWhere(
        (rule) => rule.kind == WebBillingMetricKind.daily,
      );
      final request = web.requestTemplates.firstWhere(
        (item) => item.id == daily.requestTemplateId,
      );
      expect(request.method, 'POST');
      expect(request.urlTemplate, 'https://billing.example.test/daily');
      expect(request.queryTemplate, {'date': 'today'});
      expect(request.headersTemplate, {'X-Test': r'${API_KEY}'});
      expect(request.bodyTemplate, '{"metric":"daily"}');
    },
  );

  testWidgets('API key variable saves through the provider secure key path', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final keys = _MemorySecureKeyStore();
    final controller = await pumpEditor(
      tester,
      storage: StorageService(keyStore: keys),
    );
    addTearDown(controller.dispose);

    await enterVisibleText(tester, field('显示名称'), 'My Provider');
    await enterVisibleText(
      tester,
      field('OpenAI Base URL（自动规范化为 /v1）'),
      'https://api.example.test',
    );
    await enterVisibleText(tester, field('默认模型（可选）'), 'gpt-test');
    await enterVisibleText(tester, apiKeyValue(), 'model-api-secret');
    await tapVisible(tester, find.text('保存'));
    await tester.pumpAndSettle();

    final saved = controller.configs.single;
    expect(saved.name, 'My Provider');
    expect(saved.defaultModel, 'gpt-test');
    expect(saved.apiKey, 'model-api-secret');
    expect(saved.id, isNotEmpty);
    expect(
      keys.values[ProviderKeyManager.keyFor(saved.id)],
      'model-api-secret',
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('agent_battery_state_v1'),
      isNot(contains('model-api-secret')),
    );
  });

  testWidgets(
    'saved API key shows a length-matched mask and is preserved when saved unchanged',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final keys = _MemorySecureKeyStore()
        ..values[ProviderKeyManager.keyFor('provider-a')] = 'saved-api-key';
      final controller = await pumpEditor(
        tester,
        storage: StorageService(keyStore: keys),
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpAndSettle();

      final input = apiKeyValue().evaluate().single.widget as TextField;
      expect(input.controller!.text, '•••••••••••••');
      expect(input.decoration!.hintText, isNull);
      expect(input.decoration!.labelStyle, isNull);
      expect(find.text('saved-api-key'), findsNothing);
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        keys.values[ProviderKeyManager.keyFor('provider-a')],
        'saved-api-key',
      );
      expect(
        controller.configs.single.toJson().toString(),
        isNot(contains('saved-api-key')),
      );
    },
  );

  testWidgets(
    'saved generic value masks, preserves unchanged, and replaces only user input',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final keys = _MemorySecureKeyStore()
        ..values[ProviderKeyManager.webBillingVariableKeyFor(
              'provider-a',
              'MANUAL_TOKEN',
            )] =
            'stored-generic';
      final initial = _providerWithManualVariable();
      final controller = await pumpEditor(
        tester,
        storage: StorageService(keyStore: keys),
        initial: initial,
      );
      addTearDown(controller.dispose);
      await tester.pumpAndSettle();

      final value = field('安全变量值').last;
      expect(
        (value.evaluate().single.widget as TextField).controller!.text,
        '••••••••••••••',
      );
      expect(find.text('stored-generic'), findsNothing);
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        keys.values[ProviderKeyManager.webBillingVariableKeyFor(
          'provider-a',
          'MANUAL_TOKEN',
        )],
        'stored-generic',
      );

      final replacement = 'new-generic';
      await tester.pumpWidget(const SizedBox());
      final editor = await pumpEditor(
        tester,
        storage: StorageService(keyStore: keys),
        initial: initial,
      );
      addTearDown(editor.dispose);
      await tester.pumpAndSettle();
      await enterVisibleText(tester, field('安全变量值').last, replacement);
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        keys.values[ProviderKeyManager.webBillingVariableKeyFor(
          'provider-a',
          'MANUAL_TOKEN',
        )],
        replacement,
      );
    },
  );

  testWidgets(
    'empty ordinary value subdues its unfocused label and keeps focused input blank',
    (tester) async {
      final controller = await pumpEditor(tester);
      addTearDown(controller.dispose);
      final finder = field('显示名称');
      var input = finder.evaluate().single.widget as TextField;
      expect(input.decoration!.hintText, isNull);
      expect(input.decoration!.labelStyle!.fontSize, 10);
      expect(input.decoration!.labelStyle!.color, const Color(0x59000000));

      await tapVisible(tester, finder);
      await tester.pump();
      input = finder.evaluate().single.widget as TextField;
      expect(input.controller!.text, isEmpty);
      expect(input.decoration!.hintText, isNull);
      expect(input.decoration!.labelStyle, isNull);
    },
  );

  testWidgets(
    'empty sensitive value subdues only its unfocused label and keeps focused input blank',
    (tester) async {
      final controller = await pumpEditor(tester);
      addTearDown(controller.dispose);
      final finder = apiKeyValue();
      var input = finder.evaluate().single.widget as TextField;
      expect(input.decoration!.hintText, isNull);
      expect(input.decoration!.labelStyle!.fontSize, 10);
      expect(input.decoration!.labelStyle!.color, const Color(0x59000000));

      await tapVisible(tester, finder);
      await tester.pump();
      input = finder.evaluate().single.widget as TextField;
      expect(input.controller!.text, isEmpty);
      expect(input.decoration!.hintText, isNull);
      expect(input.decoration!.labelStyle, isNull);
    },
  );

  testWidgets('saved mask survives tap and focus until the first real input', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final keys = _MemorySecureKeyStore()
      ..values[ProviderKeyManager.keyFor('provider-a')] = 'saved-api-key';
    final controller = await pumpEditor(
      tester,
      storage: StorageService(keyStore: keys),
      initial: const ProviderConfig(
        id: 'provider-a',
        name: 'Provider A',
        colorValue: 0,
        order: 0,
        enabled: true,
        baseUrl: 'https://example.test/v1',
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpAndSettle();

    final finder = apiKeyValue();
    await tapVisible(tester, finder);
    await tester.pump();
    expect(
      (finder.evaluate().single.widget as TextField).controller!.text,
      '•••••••••••••',
    );
    await tester.enterText(finder, 'replacement');
    expect(
      (finder.evaluate().single.widget as TextField).controller!.text,
      'replacement',
    );
  });

  testWidgets('hydrated API key is shown only as saved variable state', (
    tester,
  ) async {
    const secret = 'hydrated-model-api-secret';
    final controller = await pumpEditor(
      tester,
      initial: const ProviderConfig(
        id: 'provider-a',
        name: 'Provider A',
        colorValue: 0,
        order: 0,
        enabled: true,
        baseUrl: 'https://example.test/v1',
        apiKey: secret,
      ),
    );
    addTearDown(controller.dispose);

    expect(apiKeyValue(), findsOneWidget);
    expect(find.text('已安全保存；输入新值才替换'), findsOneWidget);
    expect(find.text(secret), findsNothing);
  });

  testWidgets(
    'high-version recharge and low-balance fields persist while legacy billing controls stay absent',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = await pumpEditor(
        tester,
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0xff123456,
          order: 3,
          enabled: false,
          baseUrl: 'https://example.test/v1',
          defaultModel: 'model-a',
        ),
      );
      addTearDown(controller.dispose);

      expect(field('充值/余额管理地址（可选）'), findsOneWidget);
      expect(field('低余额阈值（元，可选）'), findsOneWidget);
      expect(find.text('高级余额设置'), findsNothing);
      expect(field('余额查询 URL（完整 URL 或相对路径）'), findsNothing);
      expect(field('PuCoding Dashboard JWT（仅用于余额）'), findsNothing);
      expect(field('余额 JSON Path'), findsNothing);

      await enterVisibleText(
        tester,
        field('充值/余额管理地址（可选）'),
        'https://billing.example.test/recharge',
      );
      await enterVisibleText(tester, field('低余额阈值（元，可选）'), '12.5');
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();

      final saved = controller.configs.single;
      expect(saved.rechargeUrl, 'https://billing.example.test/recharge');
      expect(saved.lowBalanceThreshold, 12.5);
      expect(saved.colorValue, 0xff123456);
      expect(saved.order, 0);
      expect(saved.enabled, isFalse);
      expect(saved.defaultModel, 'model-a');
    },
  );

  testWidgets(
    'recharge validation rejects invalid URL and threshold can clear',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = await pumpEditor(
        tester,
        initial: const ProviderConfig(
          id: 'provider-a',
          name: 'Provider A',
          colorValue: 0,
          order: 0,
          enabled: true,
          baseUrl: 'https://example.test/v1',
          rechargeUrl: 'https://billing.example.test',
          lowBalanceThreshold: 8,
        ),
      );
      addTearDown(controller.dispose);

      await enterVisibleText(tester, field('充值/余额管理地址（可选）'), 'not-a-url');
      await tapVisible(tester, find.text('保存'));
      await tester.pump();
      expect(find.text('充值/余额管理地址必须是完整的 HTTP 或 HTTPS 地址'), findsOneWidget);

      await enterVisibleText(
        tester,
        field('充值/余额管理地址（可选）'),
        'https://billing.example.test',
      );
      await enterVisibleText(tester, field('低余额阈值（元，可选）'), '');
      await tapVisible(tester, find.text('保存'));
      await tester.pumpAndSettle();
      expect(controller.configs.single.lowBalanceThreshold, isNull);
    },
  );
}

ProviderConfig _providerWithManualVariable({RequestTemplate? request}) =>
    ProviderConfig(
      id: 'provider-a',
      name: 'Provider A',
      colorValue: 0,
      order: 0,
      enabled: true,
      baseUrl: 'https://example.test/v1',
      webBillingConfig: WebBillingConfig(
        schemaVersion: 1,
        requestTemplates: request == null ? const [] : [request],
        secretVariableDefinitions: const [
          SecretVariableDefinition(
            id: 'manual-token',
            name: 'MANUAL_TOKEN',
            displayName: 'Manual token',
            type: SecretVariableType.genericHeaderValue,
            required: false,
          ),
        ],
      ),
    );

ProviderConfig _providerWithRequest(String urlTemplate) {
  final request = RequestTemplate(
    id: 'balance-request',
    method: 'GET',
    urlTemplate: urlTemplate,
  );
  return ProviderConfig(
    id: 'provider-a',
    name: 'Provider A',
    colorValue: 0,
    order: 0,
    enabled: true,
    baseUrl: 'https://example.test/v1',
    webBillingConfig: WebBillingConfig(
      schemaVersion: 1,
      requestTemplates: [request],
      metricRules: [
        MetricRule(
          id: 'balance',
          kind: WebBillingMetricKind.balance,
          requestTemplateId: request.id,
          responseRule: const ResponseRule(scalarPath: ''),
        ),
      ],
    ),
  );
}
