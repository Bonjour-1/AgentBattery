import 'dart:convert';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/models/provider_usage.dart';
import 'package:agent_battery_flutter/models/web_billing_config.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/secure_key_store.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/services/web_billing_engine.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryKeys implements SecureKeyStore {
  final Map<String, String> values = {};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'server daily and monthly values override manual cached values',
    () async {
      final controller = await _controller(
        config: _provider(_billing()),
        usage: _currentUsage(lastBalance: 100, daily: 20, monthly: 50),
        transport: (request) async => WebBillingHttpResponse(
          200,
          jsonEncode(switch (request.uri.path) {
            '/balance' => {'value': 80},
            '/daily' => {'value': 4.25},
            _ => {'value': 11.75},
          }),
        ),
      );
      addTearDown(controller.dispose);

      final view = controller.providers['generic']!;
      expect(view.dailyUsage, 4.25);
      expect(view.dailyDisplayUsage, 4.25);
      expect(view.monthlyUsage, 11.75);
      expect(view.monthlyDisplayUsage, 11.75);
      expect(controller.totalDaily, 4.25);
      expect(controller.totalMonthly, 11.75);
    },
  );

  test(
    'showCached retains manual daily when daily fails independently',
    () async {
      final controller = await _controller(
        config: _provider(
          _billing(
            dailyUsesMissingVariable: true,
            displayPolicy: const DisplayPolicy(
              daily: MetricFailureDisplay.showCached,
              monthly: MetricFailureDisplay.showCached,
            ),
          ),
        ),
        usage: _currentUsage(lastBalance: 100, daily: 4, monthly: 10),
        transport: (request) async => WebBillingHttpResponse(
          200,
          request.uri.path == '/monthly' ? '{"value":12}' : '{"value":80}',
        ),
      );
      addTearDown(controller.dispose);

      final view = controller.providers['generic']!;
      expect(view.balance, 80);
      expect(view.dailyUsage, 4);
      expect(view.dailyDisplayUsage, 4);
      expect(view.monthlyUsage, 12);
      expect(view.monthlyDisplayUsage, 12);
      expect(controller.totalDaily, 4);
      expect(controller.totalMonthly, 12);
      expect(view.message, contains('未配置账单变量：TOKEN'));
    },
  );

  test('daily hide does not suppress successful balance or monthly', () async {
    final controller = await _controller(
      config: _provider(
        _billing(
          dailyUsesMissingVariable: true,
          displayPolicy: const DisplayPolicy(
            daily: MetricFailureDisplay.hide,
            monthly: MetricFailureDisplay.hide,
          ),
        ),
      ),
      usage: _currentUsage(lastBalance: 100, daily: 4, monthly: 10),
      transport: (request) async => WebBillingHttpResponse(
        200,
        request.uri.path == '/monthly' ? '{"value":12}' : '{"value":80}',
      ),
    );
    addTearDown(controller.dispose);

    final view = controller.providers['generic']!;
    expect(view.balance, 80);
    expect(view.dailyUsage, 4);
    expect(view.dailyDisplayUsage, isNull);
    expect(view.monthlyUsage, 12);
    expect(view.monthlyDisplayUsage, 12);
    expect(controller.totalDaily, 0);
    expect(controller.totalMonthly, 12);
  });

  test('hide retains raw usage but excludes display-aware totals', () async {
    final controller = await _controller(
      config: _provider(
        _billing(
          includeDaily: false,
          includeMonthly: false,
          displayPolicy: const DisplayPolicy(
            daily: MetricFailureDisplay.hide,
            monthly: MetricFailureDisplay.hide,
          ),
        ),
      ),
      usage: _currentUsage(lastBalance: 100, daily: 5, monthly: 50),
      transport: (_) async => const WebBillingHttpResponse(200, '{"value":80}'),
    );
    addTearDown(controller.dispose);

    final view = controller.providers['generic']!;
    expect(view.dailyUsage, 5);
    expect(view.monthlyUsage, 50);
    expect(view.dailyDisplayUsage, isNull);
    expect(view.monthlyDisplayUsage, isNull);
    expect(controller.totalDaily, 0);
    expect(controller.totalMonthly, 0);
  });

  test('estimateFallback estimates only with a previous balance', () async {
    final withPrior = await _controller(
      config: _provider(
        _billing(
          includeDaily: false,
          includeMonthly: false,
          displayPolicy: const DisplayPolicy(
            daily: MetricFailureDisplay.estimateFallback,
            monthly: MetricFailureDisplay.estimateFallback,
          ),
        ),
      ),
      usage: _currentUsage(lastBalance: 100, daily: 4, monthly: 10),
      transport: (_) async => const WebBillingHttpResponse(200, '{"value":80}'),
    );
    addTearDown(withPrior.dispose);
    expect(withPrior.providers['generic']!.dailyUsage, 24);
    expect(withPrior.providers['generic']!.dailyDisplayUsage, 24);
    expect(withPrior.providers['generic']!.monthlyUsage, 30);
    expect(withPrior.providers['generic']!.monthlyDisplayUsage, 30);

    final withoutPrior = await _controller(
      config: _provider(
        _billing(
          includeDaily: false,
          includeMonthly: false,
          displayPolicy: const DisplayPolicy(
            daily: MetricFailureDisplay.estimateFallback,
            monthly: MetricFailureDisplay.estimateFallback,
          ),
        ),
      ),
      usage: _currentUsage(lastBalance: null, daily: 4, monthly: 10),
      transport: (_) async => const WebBillingHttpResponse(200, '{"value":80}'),
    );
    addTearDown(withoutPrior.dispose);
    expect(withoutPrior.providers['generic']!.dailyUsage, 4);
    expect(withoutPrior.providers['generic']!.dailyDisplayUsage, isNull);
    expect(withoutPrior.providers['generic']!.monthlyUsage, 10);
    expect(withoutPrior.providers['generic']!.monthlyDisplayUsage, isNull);
  });

  test('concurrent refresh calls share one in-flight refresh', () async {
    var requests = 0;
    final controller = await _controller(
      config: _provider(_billing(includeDaily: false, includeMonthly: false)),
      usage: _currentUsage(lastBalance: 100, daily: 4, monthly: 10),
      refresh: false,
      transport: (_) async {
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const WebBillingHttpResponse(200, '{"value":80}');
      },
    );
    addTearDown(controller.dispose);

    final first = controller.refresh();
    final second = controller.refresh();
    await Future.wait([first, second]);

    expect(requests, 1);
  });
}

Future<BatteryController> _controller({
  required ProviderConfig config,
  required ProviderUsage usage,
  required WebBillingTransport transport,
  bool refresh = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService(keyStore: _MemoryKeys());
  await storage.save(
    AppSnapshot(providerConfigs: [config], providers: {config.id: usage}),
  );
  final controller = BatteryController(
    storage: storage,
    api: ApiClient(webBillingEngine: WebBillingEngine(transport: transport)),
  );
  await controller.initialize(refreshOnStart: false);
  if (refresh) await controller.refresh();
  return controller;
}

ProviderConfig _provider(WebBillingConfig config) => ProviderConfig(
  id: 'generic',
  name: 'Generic',
  colorValue: 0,
  order: 0,
  enabled: true,
  baseUrl: 'https://example.test/v1',
  webBillingConfig: config,
);

ProviderUsage _currentUsage({
  required double? lastBalance,
  required double daily,
  required double monthly,
}) {
  final now = DateTime.now();
  final date =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return ProviderUsage(
    date: date,
    month: date.substring(0, 7),
    lastBalance: lastBalance,
    dailyUsage: daily,
    monthlyUsage: monthly,
  );
}

WebBillingConfig _billing({
  bool includeDaily = true,
  bool includeMonthly = true,
  bool dailyUsesMissingVariable = false,
  DisplayPolicy displayPolicy = const DisplayPolicy(
    daily: MetricFailureDisplay.estimateFallback,
    monthly: MetricFailureDisplay.estimateFallback,
  ),
}) => WebBillingConfig(
  schemaVersion: 1,
  displayPolicy: displayPolicy,
  requestTemplates: [
    const RequestTemplate(
      id: 'balance',
      method: 'GET',
      urlTemplate: 'https://billing.test/balance',
    ),
    if (includeDaily)
      RequestTemplate(
        id: 'daily',
        method: 'GET',
        urlTemplate: dailyUsesMissingVariable
            ? r'https://billing.test/daily/${TOKEN}'
            : 'https://billing.test/daily',
      ),
    if (includeMonthly)
      const RequestTemplate(
        id: 'monthly',
        method: 'GET',
        urlTemplate: 'https://billing.test/monthly',
      ),
  ],
  metricRules: [
    _metric(WebBillingMetricKind.balance),
    if (includeDaily) _metric(WebBillingMetricKind.daily),
    if (includeMonthly) _metric(WebBillingMetricKind.monthly),
  ],
);

MetricRule _metric(WebBillingMetricKind kind) => MetricRule(
  id: kind.name,
  kind: kind,
  requestTemplateId: kind.name,
  responseRule: const ResponseRule(scalarPath: 'value'),
);
