import 'web_billing_config.dart';

bool isValidBaseUrl(String value) => _isValidHttpUrl(value);

bool isValidRechargeUrl(String value) => _isValidHttpUrl(value);

bool _isValidHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.hasScheme &&
      uri.hasAuthority &&
      uri.host.isNotEmpty;
}

double? parseLowBalanceThreshold(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
}

enum BalanceRequestMethod { get, post }

/// Controls the monthly value shown when a server-side monthly metric is absent.
enum MonthlyUsageFallback { balanceDelta, hidden }

/// Controls the daily value shown when a server-side daily metric is absent.
enum DailyUsageFallback { balanceDelta, hidden }

/// Defines how a billing response is reduced to one numeric metric.
///
/// `none` reads one scalar at [jsonPath]. `sum` first reads an array at
/// [itemPath], then reads and adds [jsonPath] from every array item.
enum MetricAggregation { none, sum }

const siliconFlowWalletUrl =
    'https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek';
const siliconFlowWalletHeaders =
    r'{"accept":"*/*","accept-language":"zh-CN","content-type":"application/json","priority":"u=1, i","referer":"https://cloud.siliconflow.cn/me/bills","sec-ch-ua":"\"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"150\", \"Microsoft Edge\";v=\"150\"","sec-ch-ua-mobile":"?0","sec-ch-ua-platform":"\"Windows\"","sec-fetch-dest":"empty","sec-fetch-mode":"cors","sec-fetch-site":"same-origin","user-agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0","Cookie":"${SILICONFLOW_WALLET_COOKIE}","x-subject-id":"${SILICONFLOW_WALLET_SUBJECT_ID}"}';
const siliconFlowWalletRequest = MetricRequestConfig(
  enabled: true,
  url: siliconFlowWalletUrl,
  headers: siliconFlowWalletHeaders,
  jsonPath: 'data.financialInfo.balance',
  scale: 1000000000000,
  useApiKeyAuthorization: false,
);

const siliconFlowUsageUrl =
    'https://cloud.siliconflow.cn/panel-server/api/v1/bill/aggregate_amount';
const siliconFlowUsageHeaders = siliconFlowWalletHeaders;
const siliconFlowDailyUsageRequest = MetricRequestConfig(
  enabled: true,
  url:
      '$siliconFlowUsageUrl?endTime=\${DAY_END_UNIX_MS}&startTime=\${DAY_START_UNIX_MS}',
  method: BalanceRequestMethod.get,
  headers: siliconFlowUsageHeaders,
  jsonPath: 'data.netAmount',
  useApiKeyAuthorization: false,
);
const siliconFlowMonthlyUsageRequest = MetricRequestConfig(
  enabled: true,
  url:
      '$siliconFlowUsageUrl?endTime=\${MONTH_TO_DATE_END_UNIX_MS}&startTime=\${MONTH_START_UNIX_MS}',
  method: BalanceRequestMethod.get,
  headers: siliconFlowUsageHeaders,
  jsonPath: 'data.netAmount',
  useApiKeyAuthorization: false,
);

const deepSeekCostBillUrl =
    'https://platform.deepseek.com/api/v0/usage/by_api_key/cost';
const deepSeekCostItemPath = 'data.biz_data.data[].series[].buckets[]';

/// Safe browser metadata required by DeepSeek's verified web billing request.
/// This intentionally has no Cookie: authentication is the Bearer token only.
const deepSeekCostHeaders =
    r'{"accept":"*/*","accept-language":"zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6,nb;q=0.5","referer":"https://platform.deepseek.com/usage","user-agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0","priority":"u=1, i","sec-ch-ua":"\"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"150\", \"Microsoft Edge\";v=\"150\"","sec-ch-ua-arch":"\"x86\"","sec-ch-ua-bitness":"\"64\"","sec-ch-ua-full-version":"\"150.0.4078.65\"","sec-ch-ua-full-version-list":"\"Not;A=Brand\";v=\"8.0.0.0\", \"Chromium\";v=\"150.0.7871.115\", \"Microsoft Edge\";v=\"150.0.4078.65\"","sec-ch-ua-mobile":"?0","sec-ch-ua-model":"\"\"","sec-ch-ua-platform":"\"Windows\"","sec-ch-ua-platform-version":"\"19.0.0\"","sec-fetch-dest":"empty","sec-fetch-mode":"cors","sec-fetch-site":"same-origin","x-client-bundle-id":"com.deepseek.chat","x-client-locale":"zh_CN","x-client-platform":"web","x-client-timezone-offset":"28800","x-client-version":"1.0.0","Authorization":"Bearer ${BALANCE_TOKEN}"}';

const deepSeekDailyCostRequest = MetricRequestConfig(
  enabled: true,
  url:
      '$deepSeekCostBillUrl?start=\${UTC_DAY_START_UNIX}&end=\${UTC_DAY_END_UNIX}&tz=0',
  method: BalanceRequestMethod.get,
  headers: deepSeekCostHeaders,
  aggregation: MetricAggregation.sum,
  itemPath: deepSeekCostItemPath,
  jsonPath: 'cost',
);

const deepSeekMonthlyCostRequest = MetricRequestConfig(
  enabled: true,
  url:
      '$deepSeekCostBillUrl?start=\${UTC_MONTH_START_UNIX}&end=\${UTC_MONTH_TO_DATE_END_UNIX}&tz=0',
  method: BalanceRequestMethod.get,
  headers: deepSeekCostHeaders,
  aggregation: MetricAggregation.sum,
  itemPath: deepSeekCostItemPath,
  jsonPath: 'cost',
);

/// Safe browser metadata for CodeAPI's verified web billing request.
/// This intentionally has no Cookie: authentication is the Bearer token only.
const codeApiUsageHeaders =
    r'{"accept":"*/*","accept-language":"zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6,nb;q=0.5","content-type":"application/json","origin":"https://codeapi.icu","priority":"u=1, i","referer":"https://codeapi.icu/usage","sec-ch-ua":"\"Not;A=Brand\";v=\"8\", \"Chromium\";v=\"150\", \"Microsoft Edge\";v=\"150\"","sec-ch-ua-mobile":"?0","sec-ch-ua-platform":"\"Windows\"","sec-fetch-dest":"empty","sec-fetch-mode":"cors","sec-fetch-site":"same-origin","user-agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0","Authorization":"Bearer ${BALANCE_TOKEN}"}';
const codeApiUsageUrl = 'https://codeapi.icu/api/portal/usage';
const codeApiBalanceRequest = MetricRequestConfig(
  enabled: true,
  url: codeApiUsageUrl,
  method: BalanceRequestMethod.get,
  headers: codeApiUsageHeaders,
  jsonPath: 'balance_usd',
  scale: 1,
  useApiKeyAuthorization: false,
);
const codeApiDailyUsageRequest = MetricRequestConfig(
  enabled: true,
  url: codeApiUsageUrl,
  method: BalanceRequestMethod.get,
  headers: codeApiUsageHeaders,
  jsonPath: 'today_cost_usd',
  scale: 1,
  useApiKeyAuthorization: false,
);

class MetricRequestConfig {
  const MetricRequestConfig({
    this.enabled = false,
    this.url = '',
    this.method = BalanceRequestMethod.get,
    this.body = '',
    this.headers = '',
    this.jsonPath = '',
    this.aggregation = MetricAggregation.none,
    this.itemPath = '',
    this.scale = 1,
    this.useApiKeyAuthorization = true,
  });

  final bool enabled;
  final String url;
  final BalanceRequestMethod method;
  final String body;
  final String headers;
  final String jsonPath;
  final MetricAggregation aggregation;
  final String itemPath;
  final double scale;
  final bool useApiKeyAuthorization;

  bool get isConfigured =>
      enabled &&
      url.trim().isNotEmpty &&
      jsonPath.trim().isNotEmpty &&
      scale.isFinite &&
      scale > 0 &&
      (aggregation == MetricAggregation.none || itemPath.trim().isNotEmpty);

  MetricRequestConfig copyWith({
    bool? enabled,
    String? url,
    BalanceRequestMethod? method,
    String? body,
    String? headers,
    String? jsonPath,
    MetricAggregation? aggregation,
    String? itemPath,
    double? scale,
    bool? useApiKeyAuthorization,
  }) => MetricRequestConfig(
    enabled: enabled ?? this.enabled,
    url: url ?? this.url,
    method: method ?? this.method,
    body: body ?? this.body,
    headers: headers ?? this.headers,
    jsonPath: jsonPath ?? this.jsonPath,
    aggregation: aggregation ?? this.aggregation,
    itemPath: itemPath ?? this.itemPath,
    scale: scale ?? this.scale,
    useApiKeyAuthorization:
        useApiKeyAuthorization ?? this.useApiKeyAuthorization,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'url': url,
    'method': method.name,
    'body': body,
    'headers': headers,
    'json_path': jsonPath,
    'aggregation': aggregation.name,
    'item_path': itemPath,
    'scale': scale,
    'use_api_key_authorization': useApiKeyAuthorization,
  };

  factory MetricRequestConfig.fromJson(Object? raw) {
    final json = raw is Map
        ? Map<String, Object?>.from(raw)
        : const <String, Object?>{};
    return MetricRequestConfig(
      enabled: json['enabled'] is bool && json['enabled'] as bool,
      url: json['url']?.toString() ?? '',
      method: json['method'] == 'post'
          ? BalanceRequestMethod.post
          : BalanceRequestMethod.get,
      body: json['body']?.toString() ?? '',
      headers: json['headers']?.toString() ?? '',
      jsonPath: json['json_path']?.toString() ?? '',
      aggregation: json['aggregation'] == 'sum'
          ? MetricAggregation.sum
          : MetricAggregation.none,
      itemPath: json['item_path']?.toString() ?? '',
      scale:
          json['scale'] is num &&
              (json['scale'] as num).isFinite &&
              (json['scale'] as num) > 0
          ? (json['scale'] as num).toDouble()
          : 1,
      useApiKeyAuthorization: json['use_api_key_authorization'] is bool
          ? json['use_api_key_authorization'] as bool
          : true,
    );
  }
}

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.order,
    required this.enabled,
    required this.baseUrl,
    this.apiKey = '',
    @Deprecated('Legacy billing secrets are storage-migration input only.')
    String balanceToken = '',
    @Deprecated('Legacy billing secrets are storage-migration input only.')
    String billCookie = '',
    @Deprecated('Legacy billing secrets are storage-migration input only.')
    String walletCookie = '',
    @Deprecated('Legacy billing secrets are storage-migration input only.')
    String walletSubjectId = '',
    this.defaultModel = '',
    this.rechargeUrl = '',
    this.lowBalanceThreshold,
    @Deprecated('Legacy billing is storage-migration input only.')
    bool advancedEnabled = false,
    @Deprecated('Legacy billing is storage-migration input only.')
    MetricRequestConfig balanceRequest = const MetricRequestConfig(),
    @Deprecated('Legacy billing is storage-migration input only.')
    MetricRequestConfig dailyRequest = const MetricRequestConfig(),
    @Deprecated('Legacy billing is storage-migration input only.')
    MetricRequestConfig monthlyRequest = const MetricRequestConfig(),
    @Deprecated('Legacy billing is storage-migration input only.')
    DailyUsageFallback dailyUsageFallback = DailyUsageFallback.balanceDelta,
    @Deprecated('Legacy billing is storage-migration input only.')
    MonthlyUsageFallback monthlyUsageFallback =
        MonthlyUsageFallback.balanceDelta,
    @Deprecated('Legacy billing is storage-migration input only.')
    String balanceUrl = '',
    @Deprecated('Legacy billing is storage-migration input only.')
    BalanceRequestMethod balanceMethod = BalanceRequestMethod.get,
    @Deprecated('Legacy billing is storage-migration input only.')
    String balanceBody = '',
    @Deprecated('Legacy billing is storage-migration input only.')
    String balanceHeaders = '',
    @Deprecated('Legacy billing is storage-migration input only.')
    String balanceJsonPath = '',
    @Deprecated('Legacy billing is storage-migration input only.')
    String dailyUsageJsonPath = '',
    @Deprecated('Legacy billing is storage-migration input only.')
    String monthlyUsageJsonPath = '',
    this.webBillingConfig,
  });

  final String id;
  final String name;
  final int colorValue;
  final int order;
  final bool enabled;
  final String baseUrl;
  final String apiKey;

  final String defaultModel;
  final String rechargeUrl;
  final double? lowBalanceThreshold;

  /// Generic, non-secret billing schema. It is not used by the request engine yet.
  final WebBillingConfig? webBillingConfig;

  /// Temporary source compatibility only. Legacy billing state is never held.
  @Deprecated('Use webBillingConfig.')
  String get balanceToken => '';
  @Deprecated('Use webBillingConfig.')
  String get billCookie => '';
  @Deprecated('Use webBillingConfig.')
  String get walletCookie => '';
  @Deprecated('Use webBillingConfig.')
  String get walletSubjectId => '';
  @Deprecated('Use webBillingConfig.')
  bool get advancedEnabled => false;
  @Deprecated('Use webBillingConfig.')
  MetricRequestConfig get balanceRequest => const MetricRequestConfig();
  @Deprecated('Use webBillingConfig.')
  MetricRequestConfig get dailyRequest => const MetricRequestConfig();
  @Deprecated('Use webBillingConfig.')
  MetricRequestConfig get monthlyRequest => const MetricRequestConfig();
  @Deprecated('Use webBillingConfig.')
  DailyUsageFallback get dailyUsageFallback => DailyUsageFallback.balanceDelta;
  @Deprecated('Use webBillingConfig.')
  MonthlyUsageFallback get monthlyUsageFallback =>
      MonthlyUsageFallback.balanceDelta;
  @Deprecated('Use webBillingConfig.')
  String get balanceUrl => '';
  @Deprecated('Use webBillingConfig.')
  BalanceRequestMethod get balanceMethod => BalanceRequestMethod.get;
  @Deprecated('Use webBillingConfig.')
  String get balanceBody => '';
  @Deprecated('Use webBillingConfig.')
  String get balanceHeaders => '';
  @Deprecated('Use webBillingConfig.')
  String get balanceJsonPath => '';
  @Deprecated('Use webBillingConfig.')
  String get dailyUsageJsonPath => '';
  @Deprecated('Use webBillingConfig.')
  String get monthlyUsageJsonPath => '';
  @Deprecated('Use webBillingConfig.')
  MetricRequestConfig get effectiveBalanceRequest =>
      const MetricRequestConfig();

  String get normalizedBaseUrl {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return trimmed.endsWith('/v1') ? trimmed : '$trimmed/v1';
  }

  String get maskedApiKey {
    if (apiKey.isEmpty) return '未配置';
    if (apiKey.length <= 4) return '••••';
    const visibleCharacters = 2;
    if (apiKey.length <= visibleCharacters * 2) return '••••';
    return '${apiKey.substring(0, visibleCharacters)}${'•' * (apiKey.length - visibleCharacters * 2)}${apiKey.substring(apiKey.length - visibleCharacters)}';
  }

  ProviderConfig copyWith({
    String? id,
    String? name,
    int? colorValue,
    int? order,
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? balanceToken,
    String? billCookie,
    String? walletCookie,
    String? walletSubjectId,
    String? defaultModel,
    String? rechargeUrl,
    double? lowBalanceThreshold,
    bool clearLowBalanceThreshold = false,
    bool? advancedEnabled,
    MetricRequestConfig? balanceRequest,
    MetricRequestConfig? dailyRequest,
    MetricRequestConfig? monthlyRequest,
    DailyUsageFallback? dailyUsageFallback,
    MonthlyUsageFallback? monthlyUsageFallback,
    String? balanceUrl,
    BalanceRequestMethod? balanceMethod,
    String? balanceBody,
    String? balanceHeaders,
    String? balanceJsonPath,
    String? dailyUsageJsonPath,
    String? monthlyUsageJsonPath,
    WebBillingConfig? webBillingConfig,
  }) => ProviderConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    order: order ?? this.order,
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    defaultModel: defaultModel ?? this.defaultModel,
    rechargeUrl: rechargeUrl ?? this.rechargeUrl,
    lowBalanceThreshold: clearLowBalanceThreshold
        ? null
        : lowBalanceThreshold ?? this.lowBalanceThreshold,
    webBillingConfig: webBillingConfig ?? this.webBillingConfig,
  );

  Map<String, Object?> toJson({bool includeApiKey = false}) => {
    'id': id,
    'name': name,
    'color': colorValue,
    'order': order,
    'enabled': enabled,
    'base_url': normalizedBaseUrl,
    if (includeApiKey) 'api_key': apiKey,
    'default_model': defaultModel,
    'recharge_url': rechargeUrl,
    if (lowBalanceThreshold != null)
      'low_balance_threshold': lowBalanceThreshold,
    if (webBillingConfig != null)
      'web_billing_config': webBillingConfig!.toJson(),
  };

  factory ProviderConfig.fromJson(Map<String, Object?> json) {
    return ProviderConfig(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名服务商',
      colorValue: json['color'] is num
          ? (json['color'] as num).toInt()
          : 0xff39c5bb,
      order: json['order'] is num ? (json['order'] as num).toInt() : 0,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      baseUrl: json['base_url']?.toString() ?? '',
      apiKey: json['api_key']?.toString() ?? '',
      defaultModel: json['default_model']?.toString() ?? '',
      rechargeUrl: json['recharge_url']?.toString() ?? '',
      lowBalanceThreshold: parseLowBalanceThreshold(
        json['low_balance_threshold'],
      ),

      webBillingConfig: json['web_billing_config'] == null
          ? null
          : WebBillingConfig.fromJson(json['web_billing_config']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderConfig &&
      other.toJson(includeApiKey: true).toString() ==
          toJson(includeApiKey: true).toString();
  @override
  int get hashCode => toJson(includeApiKey: true).toString().hashCode;
}

const builtinProviderTemplates = [
  ProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    colorValue: 0xff365edc,
    order: 0,
    enabled: true,
    baseUrl: 'https://api.deepseek.com/v1',
    advancedEnabled: true,
    balanceUrl: 'https://api.deepseek.com/user/balance',
    balanceJsonPath: 'balance_infos[0].total_balance',
    dailyRequest: deepSeekDailyCostRequest,
    monthlyRequest: deepSeekMonthlyCostRequest,
  ),
  ProviderConfig(
    id: 'kimi',
    name: 'Kimi',
    colorValue: 0xff39c5bb,
    order: 1,
    enabled: true,
    baseUrl: 'https://api.moonshot.cn/v1',
    advancedEnabled: true,
    balanceUrl: '/users/me/balance',
    balanceJsonPath: 'data.available_balance',
  ),
  ProviderConfig(
    id: 'pucoding',
    name: 'PuCoding',
    colorValue: 0xffe77f9e,
    order: 2,
    enabled: true,
    baseUrl: 'https://api.pucoding.com/v1',
    advancedEnabled: true,
    balanceUrl: 'https://pucoding.com/api/v1/user/account',
    balanceJsonPath: 'data.balance',
  ),
];
