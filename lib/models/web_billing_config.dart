/// Non-secret metadata describing the secure value used by a web billing rule.
enum SecretVariableType {
  bearerToken,
  cookieJar,
  cookieHeader,
  subjectId,
  genericHeaderValue,
  genericBodyValue,
}

enum BusinessSuccessOperator { equals, notEquals }

enum ResponseAggregation { none, sum }

enum WebBillingMetricKind { balance, daily, monthly }

enum MetricFailureDisplay { hide, showCached, estimateFallback }

class SecretVariableDefinition {
  const SecretVariableDefinition({
    required this.id,
    required this.name,
    required this.displayName,
    required this.type,
    required this.required,
  });

  final String id;
  final String name;
  final String displayName;
  final SecretVariableType type;
  final bool required;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'display_name': displayName,
    'type': _snakeCase(type.name),
    'required': required,
  };

  factory SecretVariableDefinition.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return SecretVariableDefinition(
      id: _string(json['id']),
      name: _string(json['name']),
      displayName: _string(json['display_name']),
      type: _enumByWireName(
        SecretVariableType.values,
        json['type'],
        SecretVariableType.genericHeaderValue,
      ),
      required: json['required'] is bool && json['required'] as bool,
    );
  }
}

class BusinessSuccessRule {
  const BusinessSuccessRule({
    this.jsonPath,
    this.operator = BusinessSuccessOperator.equals,
    this.expected,
  });

  final String? jsonPath;
  final BusinessSuccessOperator operator;

  /// A deliberately small scalar domain: string, number, bool, or null.
  final Object? expected;

  Map<String, Object?> toJson() => {
    if (jsonPath != null) 'json_path': jsonPath,
    'operator': _snakeCase(operator.name),
    if (_isJsonScalar(expected)) 'expected': expected,
  };

  factory BusinessSuccessRule.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final expected = json['expected'];
    return BusinessSuccessRule(
      jsonPath: json['json_path']?.toString(),
      operator: _enumByWireName(
        BusinessSuccessOperator.values,
        json['operator'],
        BusinessSuccessOperator.equals,
      ),
      expected: _isJsonScalar(expected) ? expected : null,
    );
  }
}

class RequestTemplate {
  const RequestTemplate({
    required this.id,
    required this.method,
    required this.urlTemplate,
    this.queryTemplate = const {},
    this.headersTemplate = const {},
    this.bodyTemplate,
    this.successRule,
  });

  final String id;
  final String method;
  final String urlTemplate;
  final Map<String, String> queryTemplate;
  final Map<String, String> headersTemplate;
  final String? bodyTemplate;
  final BusinessSuccessRule? successRule;

  Map<String, Object?> toJson() => {
    'id': id,
    'method': method,
    'url_template': urlTemplate,
    'query_template': queryTemplate,
    'headers_template': headersTemplate,
    if (bodyTemplate != null) 'body_template': bodyTemplate,
    if (successRule != null) 'success_rule': successRule!.toJson(),
  };

  factory RequestTemplate.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return RequestTemplate(
      id: _string(json['id']),
      method: _string(json['method'], fallback: 'GET'),
      urlTemplate: _string(json['url_template']),
      queryTemplate: _stringMap(json['query_template']),
      headersTemplate: _stringMap(json['headers_template']),
      bodyTemplate: json['body_template']?.toString(),
      successRule: json['success_rule'] == null
          ? null
          : BusinessSuccessRule.fromJson(json['success_rule']),
    );
  }
}

class ResponseRule {
  const ResponseRule({
    required this.scalarPath,
    this.itemPath,
    this.aggregation = ResponseAggregation.none,
  });

  final String scalarPath;
  final String? itemPath;
  final ResponseAggregation aggregation;

  Map<String, Object?> toJson() => {
    'scalar_path': scalarPath,
    if (itemPath != null) 'item_path': itemPath,
    'aggregation': aggregation.name,
  };

  factory ResponseRule.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return ResponseRule(
      scalarPath: _string(json['scalar_path']),
      itemPath: json['item_path']?.toString(),
      aggregation: json['aggregation'] == 'sum'
          ? ResponseAggregation.sum
          : ResponseAggregation.none,
    );
  }
}

class MetricRule {
  MetricRule({
    required this.id,
    required this.kind,
    required this.requestTemplateId,
    required this.responseRule,
    this.processingExpression,
    this.multiplier = 1,
    this.divisor = 1,
    this.unit = '元',
  }) : assert(multiplier.isFinite && multiplier > 0),
       assert(divisor.isFinite && divisor > 0);

  final String id;
  final WebBillingMetricKind kind;
  final String requestTemplateId;
  final ResponseRule responseRule;

  /// Optional safe data-processing DSL. When nonempty, it supersedes legacy
  /// response extraction and scaling at execution time.
  final String? processingExpression;
  final double multiplier;
  final double divisor;
  final String? unit;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'request_template_id': requestTemplateId,
    'response_rule': responseRule.toJson(),
    if (processingExpression != null)
      'processing_expression': processingExpression,
    'multiplier': multiplier,
    'divisor': divisor,
    if (unit != null) 'unit': unit,
  };

  factory MetricRule.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return MetricRule(
      id: _string(json['id']),
      kind: _enumByWireName(
        WebBillingMetricKind.values,
        json['kind'],
        WebBillingMetricKind.balance,
      ),
      requestTemplateId: _string(json['request_template_id']),
      responseRule: ResponseRule.fromJson(json['response_rule']),
      processingExpression: json['processing_expression']?.toString(),
      multiplier: _positiveNumber(json['multiplier']),
      divisor: _positiveNumber(json['divisor']),
      unit: json.containsKey('unit') ? json['unit']?.toString() : '元',
    );
  }
}

class DisplayPolicy {
  const DisplayPolicy({
    this.balance = MetricFailureDisplay.hide,
    this.daily = MetricFailureDisplay.hide,
    this.monthly = MetricFailureDisplay.hide,
  });

  final MetricFailureDisplay balance;
  final MetricFailureDisplay daily;
  final MetricFailureDisplay monthly;

  Map<String, Object?> toJson() => {
    'balance': {'on_failure': _snakeCase(balance.name)},
    'daily': {'on_failure': _snakeCase(daily.name)},
    'monthly': {'on_failure': _snakeCase(monthly.name)},
  };

  factory DisplayPolicy.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    MetricFailureDisplay read(String key) => _enumByWireName(
      MetricFailureDisplay.values,
      _jsonMap(json[key])['on_failure'],
      MetricFailureDisplay.hide,
    );
    return DisplayPolicy(
      balance: read('balance'),
      daily: read('daily'),
      monthly: read('monthly'),
    );
  }
}

class WebBillingConfig {
  const WebBillingConfig({
    required this.schemaVersion,
    this.requestTemplates = const [],
    this.secretVariableDefinitions = const [],
    this.metricRules = const [],
    this.displayPolicy = const DisplayPolicy(),
    this.source,
    this.migrationMetadata,
  });

  final int schemaVersion;
  final List<RequestTemplate> requestTemplates;
  final List<SecretVariableDefinition> secretVariableDefinitions;
  final List<MetricRule> metricRules;
  final DisplayPolicy displayPolicy;
  final String? source;
  final Map<String, Object?>? migrationMetadata;

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'request_templates': requestTemplates
        .map((value) => value.toJson())
        .toList(),
    'secret_variable_definitions': secretVariableDefinitions
        .map((value) => value.toJson())
        .toList(),
    'metric_rules': metricRules.map((value) => value.toJson()).toList(),
    'display_policy': displayPolicy.toJson(),
    if (source != null) 'source': source,
    if (migrationMetadata != null) 'migration_metadata': migrationMetadata,
  };

  factory WebBillingConfig.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return WebBillingConfig(
      schemaVersion: json['schema_version'] is num
          ? (json['schema_version'] as num).toInt()
          : 1,
      requestTemplates: _jsonList(
        json['request_templates'],
      ).map(RequestTemplate.fromJson).toList(),
      secretVariableDefinitions: _jsonList(
        json['secret_variable_definitions'],
      ).map(SecretVariableDefinition.fromJson).toList(),
      metricRules: _jsonList(
        json['metric_rules'],
      ).map(MetricRule.fromJson).toList(),
      displayPolicy: DisplayPolicy.fromJson(json['display_policy']),
      source: json['source']?.toString(),
      migrationMetadata: json['migration_metadata'] is Map
          ? _jsonMap(json['migration_metadata'])
          : null,
    );
  }
}

Map<String, Object?> _jsonMap(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : const <String, Object?>{};
List<Object?> _jsonList(Object? raw) =>
    raw is List ? List<Object?>.from(raw) : const [];
Map<String, String> _stringMap(Object? raw) =>
    _jsonMap(raw).map((key, value) => MapEntry(key, value.toString()));
String _string(Object? value, {String fallback = ''}) =>
    value?.toString() ?? fallback;
double _positiveNumber(Object? value) =>
    value is num && value.isFinite && value > 0 ? value.toDouble() : 1;
bool _isJsonScalar(Object? value) =>
    value == null || value is String || value is num || value is bool;
String _snakeCase(String value) => value.replaceAllMapped(
  RegExp(r'[A-Z]'),
  (match) => '_${match.group(0)!.toLowerCase()}',
);
T _enumByWireName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  return values.firstWhere(
    (value) => value.name == name || _snakeCase(value.name) == name,
    orElse: () => fallback,
  );
}
