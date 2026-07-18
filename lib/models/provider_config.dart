enum BalanceRequestMethod { get, post }

bool isValidBaseUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.hasScheme &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

bool isValidRechargeUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.hasScheme &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

double? parseLowBalanceThreshold(Object? value) {
  final threshold = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return threshold != null && threshold.isFinite && threshold >= 0
      ? threshold
      : null;
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
    this.balanceToken = '',
    this.defaultModel = '',
    this.advancedEnabled = false,
    this.balanceUrl = '',
    this.balanceMethod = BalanceRequestMethod.get,
    this.balanceBody = '',
    this.balanceHeaders = '',
    this.balanceJsonPath = '',
    this.dailyUsageJsonPath = '',
    this.monthlyUsageJsonPath = '',
    this.rechargeUrl = '',
    this.lowBalanceThreshold,
  });

  final String id;
  final String name;
  final int colorValue;
  final int order;
  final bool enabled;
  final String baseUrl;
  final String apiKey;
  final String balanceToken;
  final String defaultModel;
  final bool advancedEnabled;
  final String balanceUrl;
  final BalanceRequestMethod balanceMethod;
  final String balanceBody;
  final String balanceHeaders;
  final String balanceJsonPath;
  final String dailyUsageJsonPath;
  final String monthlyUsageJsonPath;
  final String rechargeUrl;
  final double? lowBalanceThreshold;

  String get normalizedBaseUrl {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return trimmed.endsWith('/v1') ? trimmed : '$trimmed/v1';
  }

  String get maskedApiKey {
    if (apiKey.isEmpty) return '未配置';
    if (apiKey.length <= 4) return '••••';
    const visibleCharacters = 2;
    if (apiKey.length <= visibleCharacters * 2) return '••••';
    return '${apiKey.substring(0, visibleCharacters)}'
        '${'•' * (apiKey.length - visibleCharacters * 2)}'
        '${apiKey.substring(apiKey.length - visibleCharacters)}';
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
    String? defaultModel,
    bool? advancedEnabled,
    String? balanceUrl,
    BalanceRequestMethod? balanceMethod,
    String? balanceBody,
    String? balanceHeaders,
    String? balanceJsonPath,
    String? dailyUsageJsonPath,
    String? monthlyUsageJsonPath,
    String? rechargeUrl,
    double? lowBalanceThreshold,
    bool clearLowBalanceThreshold = false,
  }) => ProviderConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    order: order ?? this.order,
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    balanceToken: balanceToken ?? this.balanceToken,
    defaultModel: defaultModel ?? this.defaultModel,
    advancedEnabled: advancedEnabled ?? this.advancedEnabled,
    balanceUrl: balanceUrl ?? this.balanceUrl,
    balanceMethod: balanceMethod ?? this.balanceMethod,
    balanceBody: balanceBody ?? this.balanceBody,
    balanceHeaders: balanceHeaders ?? this.balanceHeaders,
    balanceJsonPath: balanceJsonPath ?? this.balanceJsonPath,
    dailyUsageJsonPath: dailyUsageJsonPath ?? this.dailyUsageJsonPath,
    monthlyUsageJsonPath: monthlyUsageJsonPath ?? this.monthlyUsageJsonPath,
    rechargeUrl: rechargeUrl ?? this.rechargeUrl,
    lowBalanceThreshold: clearLowBalanceThreshold
        ? null
        : lowBalanceThreshold ?? this.lowBalanceThreshold,
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
    'advanced_enabled': advancedEnabled,
    'balance_url': balanceUrl,
    'balance_method': balanceMethod.name,
    'balance_body': balanceBody,
    'balance_headers': balanceHeaders,
    'balance_json_path': balanceJsonPath,
    'daily_usage_json_path': dailyUsageJsonPath,
    'monthly_usage_json_path': monthlyUsageJsonPath,
    'recharge_url': rechargeUrl,
    if (lowBalanceThreshold != null)
      'low_balance_threshold': lowBalanceThreshold,
  };

  factory ProviderConfig.fromJson(Map<String, Object?> json) => ProviderConfig(
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
    advancedEnabled:
        json['advanced_enabled'] is bool && json['advanced_enabled'] as bool,
    balanceUrl: json['balance_url']?.toString() ?? '',
    balanceMethod: json['balance_method'] == 'post'
        ? BalanceRequestMethod.post
        : BalanceRequestMethod.get,
    balanceBody: json['balance_body']?.toString() ?? '',
    balanceHeaders: json['balance_headers']?.toString() ?? '',
    balanceJsonPath: json['balance_json_path']?.toString() ?? '',
    dailyUsageJsonPath: json['daily_usage_json_path']?.toString() ?? '',
    monthlyUsageJsonPath: json['monthly_usage_json_path']?.toString() ?? '',
    rechargeUrl: json['recharge_url']?.toString() ?? '',
    lowBalanceThreshold: parseLowBalanceThreshold(
      json['low_balance_threshold'],
    ),
  );

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
