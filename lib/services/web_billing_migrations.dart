import 'dart:convert';

import '../models/provider_config.dart';
import '../models/web_billing_config.dart';

/// Parse-only representation of the retired provider billing JSON schema.
///
/// This type is deliberately kept out of [ProviderConfig]: old billing data is
/// consumed during storage loading and is never retained by the runtime model.
class LegacyBillingSnapshot {
  const LegacyBillingSnapshot({
    required this.advancedEnabled,
    required this.balance,
    required this.daily,
    required this.monthly,
  });

  final bool advancedEnabled;
  final MetricRequestConfig balance;
  final MetricRequestConfig daily;
  final MetricRequestConfig monthly;

  factory LegacyBillingSnapshot.fromJson(Map<String, Object?> json) {
    final legacyBalance = MetricRequestConfig(
      enabled: true,
      url: json['balance_url']?.toString() ?? '',
      method: json['balance_method'] == 'post'
          ? BalanceRequestMethod.post
          : BalanceRequestMethod.get,
      body: json['balance_body']?.toString() ?? '',
      headers: json['balance_headers']?.toString() ?? '',
      jsonPath: json['balance_json_path']?.toString() ?? '',
    );
    final parsedBalance = MetricRequestConfig.fromJson(json['balance_request']);
    return LegacyBillingSnapshot(
      advancedEnabled: json['advanced_enabled'] == true,
      balance: parsedBalance.isConfigured ? parsedBalance : legacyBalance,
      daily: MetricRequestConfig.fromJson(json['daily_request']),
      monthly: MetricRequestConfig.fromJson(json['monthly_request']),
    );
  }

  bool get hasConfiguredRequest =>
      balance.isConfigured || daily.isConfigured || monthly.isConfigured;
}

/// Non-destructive, opt-in templates for known legacy billing configurations.
///
/// These factories contain only request structure and secret-variable metadata.
/// They neither read nor write credential values, and callers must explicitly
/// choose to attach their result to a provider.
WebBillingConfig deepSeekWebBillingConfig() => WebBillingConfig(
  schemaVersion: 1,
  source: 'legacy_deepseek',
  migrationMetadata: const {
    'source': 'legacy_deepseek',
    'legacy_fallback_enabled': true,
    'cleanup_eligible': false,
  },
  secretVariableDefinitions: const [
    SecretVariableDefinition(
      id: 'deepseek-api-key',
      name: 'DEEPSEEK_API_KEY',
      displayName: 'DeepSeek API Key',
      type: SecretVariableType.bearerToken,
      required: true,
    ),
    SecretVariableDefinition(
      id: 'deepseek-web-bearer',
      name: 'DEEPSEEK_WEB_BEARER',
      displayName: 'DeepSeek 网页账单令牌',
      type: SecretVariableType.bearerToken,
      required: true,
    ),
  ],
  requestTemplates: [
    RequestTemplate(
      id: 'deepseek-balance',
      method: 'GET',
      urlTemplate: 'https://api.deepseek.com/user/balance',
      headersTemplate: const {'Authorization': r'Bearer ${DEEPSEEK_API_KEY}'},
    ),
    RequestTemplate(
      id: 'deepseek-daily-cost',
      method: 'GET',
      urlTemplate: deepSeekCostBillUrl,
      queryTemplate: const {
        'start': r'${UTC_DAY_START_UNIX}',
        'end': r'${UTC_DAY_END_UNIX}',
        'tz': '0',
      },
      headersTemplate: _headersWithSecret(
        deepSeekCostHeaders,
        legacyVariable: 'BALANCE_TOKEN',
        replacementVariable: 'DEEPSEEK_WEB_BEARER',
      ),
    ),
    RequestTemplate(
      id: 'deepseek-monthly-cost',
      method: 'GET',
      urlTemplate: deepSeekCostBillUrl,
      queryTemplate: const {
        'start': r'${UTC_MONTH_START_UNIX}',
        'end': r'${UTC_MONTH_TO_DATE_END_UNIX}',
        'tz': '0',
      },
      headersTemplate: _headersWithSecret(
        deepSeekCostHeaders,
        legacyVariable: 'BALANCE_TOKEN',
        replacementVariable: 'DEEPSEEK_WEB_BEARER',
      ),
    ),
  ],
  metricRules: [
    MetricRule(
      id: 'deepseek-balance',
      kind: WebBillingMetricKind.balance,
      requestTemplateId: 'deepseek-balance',
      responseRule: const ResponseRule(
        scalarPath: 'balance_infos[0].total_balance',
      ),
    ),
    _deepSeekCostMetric(
      'deepseek-daily',
      WebBillingMetricKind.daily,
      'deepseek-daily-cost',
    ),
    _deepSeekCostMetric(
      'deepseek-monthly',
      WebBillingMetricKind.monthly,
      'deepseek-monthly-cost',
    ),
  ],
);

WebBillingConfig siliconFlowWebBillingConfig() => WebBillingConfig(
  schemaVersion: 1,
  source: 'legacy_siliconflow',
  migrationMetadata: const {
    'source': 'legacy_siliconflow',
    'legacy_fallback_enabled': true,
    'cleanup_eligible': false,
  },
  secretVariableDefinitions: const [
    SecretVariableDefinition(
      id: 'siliconflow-cookie',
      name: 'COOKIE',
      displayName: 'SiliconFlow Cookie',
      type: SecretVariableType.cookieHeader,
      required: true,
    ),
    SecretVariableDefinition(
      id: 'siliconflow-subject-id',
      name: 'SUBJECT_ID',
      displayName: 'SiliconFlow Subject ID',
      type: SecretVariableType.subjectId,
      required: true,
    ),
  ],
  requestTemplates: [
    RequestTemplate(
      id: 'siliconflow-balance',
      method: 'GET',
      urlTemplate: siliconFlowWalletUrl,
      headersTemplate: _siliconFlowHeaders(),
      successRule: const BusinessSuccessRule(jsonPath: 'code', expected: 20000),
    ),
    RequestTemplate(
      id: 'siliconflow-daily',
      method: 'GET',
      urlTemplate: siliconFlowUsageUrl,
      queryTemplate: const {
        'startTime': r'${DAY_START_UNIX_MS}',
        'endTime': r'${DAY_END_UNIX_MS}',
      },
      headersTemplate: _siliconFlowHeaders(),
      successRule: const BusinessSuccessRule(jsonPath: 'code', expected: 20000),
    ),
    RequestTemplate(
      id: 'siliconflow-monthly',
      method: 'GET',
      urlTemplate: siliconFlowUsageUrl,
      queryTemplate: const {
        'startTime': r'${MONTH_START_UNIX_MS}',
        'endTime': r'${MONTH_TO_DATE_END_UNIX_MS}',
      },
      headersTemplate: _siliconFlowHeaders(),
      successRule: const BusinessSuccessRule(jsonPath: 'code', expected: 20000),
    ),
  ],
  metricRules: [
    MetricRule(
      id: 'siliconflow-balance',
      kind: WebBillingMetricKind.balance,
      requestTemplateId: 'siliconflow-balance',
      responseRule: const ResponseRule(
        scalarPath: 'data.financialInfo.balance',
      ),
      divisor: 1000000000000,
    ),
    MetricRule(
      id: 'siliconflow-daily',
      kind: WebBillingMetricKind.daily,
      requestTemplateId: 'siliconflow-daily',
      responseRule: const ResponseRule(scalarPath: 'data.netAmount'),
    ),
    MetricRule(
      id: 'siliconflow-monthly',
      kind: WebBillingMetricKind.monthly,
      requestTemplateId: 'siliconflow-monthly',
      responseRule: const ResponseRule(scalarPath: 'data.netAmount'),
    ),
  ],
);

WebBillingConfig codeApiWebBillingConfig() => WebBillingConfig(
  schemaVersion: 1,
  source: 'legacy_codeapi',
  migrationMetadata: const {
    'source': 'legacy_codeapi',
    'legacy_fallback_enabled': true,
    'cleanup_eligible': false,
  },
  secretVariableDefinitions: const [
    SecretVariableDefinition(
      id: 'codeapi-web-bearer',
      name: 'CODEAPI_WEB_BEARER',
      displayName: 'CodeAPI 网页账单令牌',
      type: SecretVariableType.bearerToken,
      required: true,
    ),
  ],
  requestTemplates: [
    RequestTemplate(
      id: 'codeapi-usage',
      method: 'GET',
      urlTemplate: codeApiUsageUrl,
      headersTemplate: _headersWithSecret(
        codeApiUsageHeaders,
        legacyVariable: 'BALANCE_TOKEN',
        replacementVariable: 'CODEAPI_WEB_BEARER',
      ),
    ),
  ],
  metricRules: [
    MetricRule(
      id: 'codeapi-balance',
      kind: WebBillingMetricKind.balance,
      requestTemplateId: 'codeapi-usage',
      responseRule: const ResponseRule(scalarPath: 'balance_usd'),
      unit: 'USD',
    ),
    MetricRule(
      id: 'codeapi-daily',
      kind: WebBillingMetricKind.daily,
      requestTemplateId: 'codeapi-usage',
      responseRule: const ResponseRule(scalarPath: 'today_cost_usd'),
      unit: 'USD',
    ),
  ],
);

/// Attaches a factory only when a complete, known legacy template matches.
/// Existing generic data always wins, so user-imported configuration is never overwritten.
ProviderConfig migrateLegacyProviderToWebBillingConfig(
  ProviderConfig config, [
  LegacyBillingSnapshot? legacy,
]) {
  if (config.webBillingConfig != null) return config;
  final recognized = legacy == null
      ? null
      : _recognizedLegacyConfig(config.id, legacy);
  if (recognized != null) {
    return config.copyWith(webBillingConfig: recognized);
  }
  if (legacy != null && legacy.hasConfiguredRequest) {
    return config.copyWith(
      webBillingConfig: _genericLegacyWebBillingConfig(config.id, legacy),
    );
  }
  final migrated = switch (config.id) {
    'deepseek' when _isDeepSeekLegacy(config) => deepSeekWebBillingConfig(),
    'siliconflow' when _isSiliconFlowLegacy(config) =>
      siliconFlowWebBillingConfig(),
    'codeapi' ||
    'codeapi-claude' when _isCodeApiLegacy(config) => codeApiWebBillingConfig(),
    _ => null,
  };
  return migrated == null
      ? config
      : config.copyWith(webBillingConfig: migrated);
}

WebBillingConfig? _recognizedLegacyConfig(
  String id,
  LegacyBillingSnapshot legacy,
) => switch (id) {
  'deepseek'
      when legacy.advancedEnabled &&
          legacy.balance.url == 'https://api.deepseek.com/user/balance' &&
          legacy.balance.jsonPath == 'balance_infos[0].total_balance' &&
          _same(legacy.daily, deepSeekDailyCostRequest) &&
          _same(legacy.monthly, deepSeekMonthlyCostRequest) =>
    deepSeekWebBillingConfig(),
  'siliconflow'
      when legacy.advancedEnabled &&
          _same(legacy.balance, siliconFlowWalletRequest) &&
          _same(legacy.daily, siliconFlowDailyUsageRequest) &&
          _same(legacy.monthly, siliconFlowMonthlyUsageRequest) =>
    siliconFlowWebBillingConfig(),
  'codeapi' || 'codeapi-claude'
      when legacy.advancedEnabled &&
          _same(legacy.balance, codeApiBalanceRequest) &&
          _same(legacy.daily, codeApiDailyUsageRequest) &&
          !legacy.monthly.isConfigured =>
    codeApiWebBillingConfig(),
  _ => null,
};

/// Returns true only when [config] carries the exact factory metadata and its
/// current legacy request fields still match the recognized legacy shape.
bool isRecognizedLegacyWebBillingConfig(ProviderConfig config) {
  final source = config.webBillingConfig?.source;
  return switch (config.id) {
    'deepseek' => source == 'legacy_deepseek',
    'siliconflow' => source == 'legacy_siliconflow',
    'codeapi' || 'codeapi-claude' => source == 'legacy_codeapi',
    _ => false,
  };
}

WebBillingConfig _genericLegacyWebBillingConfig(
  String providerId,
  LegacyBillingSnapshot legacy,
) {
  final requests = <RequestTemplate>[];
  final rules = <MetricRule>[];
  final secretDefinitions = <SecretVariableDefinition>[];
  final metadata = <String, Object?>{
    'source': 'legacy_provider_config',
    'provider_id': providerId,
    'legacy_advanced_enabled': legacy.advancedEnabled,
    'cleanup_eligible': true,
  };
  void add(WebBillingMetricKind kind, MetricRequestConfig request) {
    if (!request.isConfigured) return;
    final id = kind.name;
    final headerResult = _legacyHeaders(request.headers);
    final headers = <String, String>{...headerResult.headers};
    if (request.useApiKeyAuthorization &&
        !headers.containsKey('Authorization')) {
      headers['Authorization'] = r'Bearer ${API_KEY}';
      if (!secretDefinitions.any((item) => item.name == 'API_KEY')) {
        secretDefinitions.add(
          const SecretVariableDefinition(
            id: 'legacy-api-key',
            name: 'API_KEY',
            displayName: 'API Key',
            type: SecretVariableType.bearerToken,
            required: true,
          ),
        );
      }
    }
    if (headerResult.raw != null) {
      metadata['${kind.name}_unparsed_headers'] = headerResult.raw;
    }
    final url = _splitLegacyUrl(request.url);
    final templateValues = [
      request.url,
      request.body,
      request.headers,
      request.jsonPath,
      request.itemPath,
    ];
    for (final value in templateValues) {
      for (final match in RegExp(
        r'\$\{([A-Za-z][A-Za-z0-9_]*)\}',
      ).allMatches(value)) {
        final variableName = match.group(1)!;
        if (_isLegacyRuntimeVariable(variableName) ||
            secretDefinitions.any((item) => item.name == variableName)) {
          continue;
        }
        secretDefinitions.add(
          SecretVariableDefinition(
            id: 'legacy-${variableName.toLowerCase().replaceAll('_', '-')}',
            name: variableName,
            displayName: variableName,
            type: _legacySecretType(variableName),
            required: true,
          ),
        );
      }
    }
    requests.add(
      RequestTemplate(
        id: id,
        method: request.method == BalanceRequestMethod.post ? 'POST' : 'GET',
        urlTemplate: url.base,
        queryTemplate: url.query,
        headersTemplate: headers,
        bodyTemplate: request.body.isEmpty ? null : request.body,
      ),
    );
    rules.add(
      MetricRule(
        id: id,
        kind: kind,
        requestTemplateId: id,
        responseRule: ResponseRule(
          scalarPath: request.jsonPath,
          itemPath: request.aggregation == MetricAggregation.sum
              ? request.itemPath
              : null,
          aggregation: request.aggregation == MetricAggregation.sum
              ? ResponseAggregation.sum
              : ResponseAggregation.none,
        ),
        divisor: request.scale,
      ),
    );
  }

  add(WebBillingMetricKind.balance, legacy.balance);
  add(WebBillingMetricKind.daily, legacy.daily);
  add(WebBillingMetricKind.monthly, legacy.monthly);
  return WebBillingConfig(
    schemaVersion: 1,
    source: 'legacy_provider_config',
    requestTemplates: requests,
    secretVariableDefinitions: secretDefinitions,
    metricRules: rules,
    migrationMetadata: metadata,
  );
}

bool _isLegacyRuntimeVariable(String value) =>
    value.contains('DAY_') ||
    value.contains('MONTH_') ||
    value == 'DATE' ||
    value == 'TZ_HOURS';

SecretVariableType _legacySecretType(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('cookie')) return SecretVariableType.cookieHeader;
  if (normalized.contains('subject')) return SecretVariableType.subjectId;
  if (normalized.contains('token') || normalized.contains('key')) {
    return SecretVariableType.bearerToken;
  }
  return SecretVariableType.genericHeaderValue;
}

({String base, Map<String, String> query}) _splitLegacyUrl(String value) {
  final marker = value.indexOf('?');
  if (marker < 0) return (base: value, query: const {});
  final query = <String, String>{};
  for (final item in value.substring(marker + 1).split('&')) {
    final separator = item.indexOf('=');
    if (separator < 0) {
      if (item.isNotEmpty) query[item] = '';
    } else {
      query[item.substring(0, separator)] = item.substring(separator + 1);
    }
  }
  return (base: value.substring(0, marker), query: query);
}

({Map<String, String> headers, String? raw}) _legacyHeaders(String value) {
  if (value.trim().isEmpty) return (headers: const {}, raw: null);
  try {
    return (
      headers: _headersWithSecret(
        value,
        legacyVariable: '',
        replacementVariable: '',
      ),
      raw: null,
    );
  } catch (_) {
    return (headers: const {}, raw: value);
  }
}

MetricRule _deepSeekCostMetric(
  String id,
  WebBillingMetricKind kind,
  String requestId,
) => MetricRule(
  id: id,
  kind: kind,
  requestTemplateId: requestId,
  responseRule: const ResponseRule(
    scalarPath: 'cost',
    itemPath: r'$.data.biz_data.data[*].series[*].buckets[*]',
    aggregation: ResponseAggregation.sum,
  ),
);

Map<String, String> _headersWithSecret(
  String encoded, {
  required String legacyVariable,
  required String replacementVariable,
}) => Map<String, String>.unmodifiable(
  (jsonDecode(encoded) as Map).map(
    (key, value) => MapEntry(
      key.toString(),
      value.toString().replaceAll(
        '\${$legacyVariable}',
        '\${$replacementVariable}',
      ),
    ),
  ),
);

Map<String, String> _siliconFlowHeaders() => Map<String, String>.unmodifiable(
  _headersWithSecret(
    siliconFlowWalletHeaders,
    legacyVariable: 'SILICONFLOW_WALLET_COOKIE',
    replacementVariable: 'COOKIE',
  ).map(
    (key, value) => MapEntry(
      key,
      value.replaceAll(r'${SILICONFLOW_WALLET_SUBJECT_ID}', r'${SUBJECT_ID}'),
    ),
  ),
);

bool _same(MetricRequestConfig a, MetricRequestConfig b) =>
    a.toJson().toString() == b.toJson().toString();
bool _isDeepSeekLegacy(ProviderConfig c) =>
    c.advancedEnabled &&
    c.balanceUrl == 'https://api.deepseek.com/user/balance' &&
    c.balanceJsonPath == 'balance_infos[0].total_balance' &&
    _same(c.dailyRequest, deepSeekDailyCostRequest) &&
    _same(c.monthlyRequest, deepSeekMonthlyCostRequest);
bool _isSiliconFlowLegacy(ProviderConfig c) =>
    c.advancedEnabled &&
    _same(c.balanceRequest, siliconFlowWalletRequest) &&
    _same(c.dailyRequest, siliconFlowDailyUsageRequest) &&
    _same(c.monthlyRequest, siliconFlowMonthlyUsageRequest);
bool _isCodeApiLegacy(ProviderConfig c) =>
    c.advancedEnabled &&
    _same(c.balanceRequest, codeApiBalanceRequest) &&
    _same(c.dailyRequest, codeApiDailyUsageRequest) &&
    !c.monthlyRequest.isConfigured;
