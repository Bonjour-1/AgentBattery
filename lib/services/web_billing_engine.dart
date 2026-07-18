import 'dart:async';
import 'dart:convert';

import '../models/web_billing_config.dart';
import 'api_client.dart' show JsonPathExtractor;
import 'secure_key_store.dart';
import 'web_billing_expression.dart';

/// Reads a non-configured secret value without exposing it to logs or errors.
typedef WebBillingSecretResolver =
    Future<String?> Function(String providerId, String variableName);

typedef WebBillingTransport =
    Future<WebBillingHttpResponse> Function(RawHttpRequest request);

/// Minimal injected HTTP response used by generic billing transports.
class WebBillingHttpResponse {
  const WebBillingHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class RawHttpRequest {
  const RawHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class WebBillingMetricResult {
  const WebBillingMetricResult._({
    required this.requested,
    required this.succeeded,
    this.value,
    this.failure,
  });

  const WebBillingMetricResult.unconfigured()
    : this._(requested: false, succeeded: false);
  const WebBillingMetricResult.success(double value)
    : this._(requested: true, succeeded: true, value: value);
  const WebBillingMetricResult.failed(String failure)
    : this._(requested: true, succeeded: false, failure: failure);

  final bool requested;
  final bool succeeded;
  final double? value;
  final String? failure;
}

class WebBillingExecutionResult {
  const WebBillingExecutionResult({
    required this.balance,
    required this.daily,
    required this.monthly,
  });

  final WebBillingMetricResult balance;
  final WebBillingMetricResult daily;
  final WebBillingMetricResult monthly;
}

/// Executes only generic web-billing templates. It has no provider special cases.
class WebBillingEngine {
  WebBillingEngine({
    WebBillingSecretResolver? secretResolver,
    WebBillingTransport? transport,
    this.timeout = const Duration(seconds: 12),
  }) : _secretResolver = secretResolver ?? _unconfiguredSecret,
       _transport = transport ?? _unsupportedTransport;

  final WebBillingSecretResolver _secretResolver;
  final WebBillingTransport _transport;
  final Duration timeout;

  factory WebBillingEngine.withProviderKeyManager(
    ProviderKeyManager keyManager, {
    required WebBillingTransport transport,
    Duration timeout = const Duration(seconds: 12),
  }) => WebBillingEngine(
    transport: transport,
    timeout: timeout,
    secretResolver: (providerId, variableName) =>
        keyManager.readWebBillingVariable(
          providerId: providerId,
          variableId: variableName,
        ),
  );

  static Future<String?> _unconfiguredSecret(String _, String _) async => null;
  static Future<WebBillingHttpResponse> _unsupportedTransport(
    RawHttpRequest _,
  ) => Future.error(const WebBillingFailure('网络请求失败'));

  static bool isExecutable(WebBillingConfig? config) {
    if (config == null ||
        config.requestTemplates.isEmpty ||
        config.metricRules.isEmpty) {
      return false;
    }
    final requestIds = config.requestTemplates
        .map((request) => request.id)
        .toSet();
    return config.metricRules.any(
      (metric) =>
          metric.kind == WebBillingMetricKind.balance &&
          requestIds.contains(metric.requestTemplateId) &&
          (metric.processingExpression?.trim().isNotEmpty == true ||
              metric.responseRule.scalarPath.trim().isNotEmpty),
    );
  }

  Future<WebBillingExecutionResult> execute({
    required String providerId,
    required WebBillingConfig config,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final results = <WebBillingMetricKind, WebBillingMetricResult>{};
    for (final kind in WebBillingMetricKind.values) {
      final metric = config.metricRules
          .where((rule) => rule.kind == kind)
          .firstOrNull;
      results[kind] = metric == null
          ? const WebBillingMetricResult.unconfigured()
          : await _executeMetric(providerId, config, metric, timestamp);
    }
    return WebBillingExecutionResult(
      balance: results[WebBillingMetricKind.balance]!,
      daily: results[WebBillingMetricKind.daily]!,
      monthly: results[WebBillingMetricKind.monthly]!,
    );
  }

  Future<WebBillingMetricResult> _executeMetric(
    String providerId,
    WebBillingConfig config,
    MetricRule metric,
    DateTime now,
  ) async {
    final request = config.requestTemplates
        .where((template) => template.id == metric.requestTemplateId)
        .firstOrNull;
    if (request == null || !_validMetric(metric)) {
      return const WebBillingMetricResult.failed('账单请求配置不完整');
    }
    try {
      final variables = await _variables(providerId, config, now);
      final resolved = _buildRequest(request, variables);
      final response = await _transport(resolved).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WebBillingFailure('账单请求 HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (!_matchesSuccessRule(decoded, request.successRule)) {
        throw const WebBillingFailure('账单业务成功规则不匹配');
      }
      final expression = metric.processingExpression?.trim();
      if (expression?.isNotEmpty == true) {
        return WebBillingMetricResult.success(
          WebBillingExpression.evaluate(expression!, decoded),
        );
      }
      final value = _extractValue(decoded, metric.responseRule);
      final scaled = value * metric.multiplier / metric.divisor;
      if (!scaled.isFinite) throw const FormatException();
      return WebBillingMetricResult.success(scaled);
    } on WebBillingFailure catch (failure) {
      return WebBillingMetricResult.failed(failure.message);
    } on WebBillingExpressionException {
      return const WebBillingMetricResult.failed(
        WebBillingExpressionException.safeMessage,
      );
    } on TimeoutException {
      return const WebBillingMetricResult.failed('账单请求超时');
    } catch (_) {
      return const WebBillingMetricResult.failed('账单响应格式异常');
    }
  }

  bool _validMetric(MetricRule metric) {
    if (metric.processingExpression?.trim().isNotEmpty == true) return true;
    return metric.responseRule.scalarPath.trim().isNotEmpty &&
        metric.multiplier.isFinite &&
        metric.multiplier > 0 &&
        metric.divisor.isFinite &&
        metric.divisor > 0 &&
        (metric.responseRule.aggregation != ResponseAggregation.sum ||
            (metric.responseRule.itemPath?.trim().isNotEmpty ?? false));
  }

  Future<Map<String, String>> _variables(
    String providerId,
    WebBillingConfig config,
    DateTime now,
  ) async {
    final values = _systemVariables(now);
    for (final secret in config.secretVariableDefinitions) {
      final secureValue = await _secretResolver(providerId, secret.name);
      final value = secureValue?.isNotEmpty == true ? secureValue : null;
      if ((value == null || value.isEmpty) && secret.required) {
        throw WebBillingFailure(
          '未配置账单变量：${secret.displayName.isEmpty ? secret.name : secret.displayName}',
        );
      }
      if (value != null) values[secret.name] = value;
    }
    return values;
  }

  RawHttpRequest _buildRequest(
    RequestTemplate template,
    Map<String, String> values,
  ) {
    final method = template.method.trim().toUpperCase();
    if (method != 'GET' && method != 'POST') {
      throw const WebBillingFailure('账单请求配置不完整');
    }
    final url = _resolve(template.urlTemplate, values);
    final baseUri = Uri.tryParse(url);
    if (baseUri == null || !baseUri.hasScheme || !baseUri.hasAuthority) {
      throw const WebBillingFailure('账单请求配置不完整');
    }
    final query = <String, String>{...baseUri.queryParameters};
    for (final entry in template.queryTemplate.entries) {
      query[_resolve(entry.key, values)] = _resolve(entry.value, values);
    }
    final headers = <String, String>{
      for (final entry in template.headersTemplate.entries)
        _resolve(entry.key, values): _resolve(entry.value, values),
    };
    final body = template.bodyTemplate == null
        ? null
        : _resolve(template.bodyTemplate!, values);
    return RawHttpRequest(
      method: method,
      uri: baseUri.replace(queryParameters: query.isEmpty ? null : query),
      headers: Map.unmodifiable(headers),
      body: body,
    );
  }

  String _resolve(String template, Map<String, String> values) => template
      .replaceAllMapped(RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'), (match) {
        final name = match.group(1)!;
        final value = values[name];
        if (value == null) throw WebBillingFailure('未配置账单变量：$name');
        return value;
      });

  bool _matchesSuccessRule(Object? decoded, BusinessSuccessRule? rule) {
    if (rule == null ||
        rule.jsonPath == null ||
        rule.jsonPath!.trim().isEmpty) {
      return true;
    }
    final actual = _extractScalar(decoded, rule.jsonPath!);
    final equal = actual != null && _scalarEquals(actual, rule.expected);
    return rule.operator == BusinessSuccessOperator.equals ? equal : !equal;
  }

  double _extractValue(Object? decoded, ResponseRule rule) {
    if (rule.aggregation == ResponseAggregation.none) {
      final value = _number(_extractScalar(decoded, rule.scalarPath));
      if (value == null) throw const FormatException();
      return value;
    }
    final items = _extractAll(decoded, rule.itemPath!);
    if (items == null || items.isEmpty) throw const FormatException();
    var sum = 0.0;
    for (final item in items) {
      final value = _number(_extractScalar(item, rule.scalarPath));
      if (value == null) throw const FormatException();
      sum += value;
    }
    return sum;
  }

  Object? _extractScalar(Object? root, String path) =>
      JsonPathExtractor.extract(root, _normalisePath(path));
  List<Object?>? _extractAll(Object? root, String path) =>
      JsonPathExtractor.extractAll(root, _normalisePath(path));
  String _normalisePath(String path) =>
      path.trim().replaceFirst(RegExp(r'^\$\.?'), '').replaceAll('[*]', '[]');

  bool _scalarEquals(Object actual, Object? expected) {
    if (actual is num && expected is num) return actual == expected;
    return actual == expected;
  }

  double? _number(Object? value) => switch (value) {
    num number when number.isFinite => number.toDouble(),
    String text => double.tryParse(text.trim()),
    _ => null,
  };

  Map<String, String> _systemVariables(DateTime now) {
    final local = now.toLocal();
    final localDayStart = DateTime(local.year, local.month, local.day);
    final localDayEnd = localDayStart.add(const Duration(days: 1));
    final localMonthStart = DateTime(local.year, local.month);
    final utc = now.toUtc();
    final utcDayStart = DateTime.utc(utc.year, utc.month, utc.day);
    final utcDayEnd = utcDayStart.add(const Duration(days: 1));
    final utcMonthStart = DateTime.utc(utc.year, utc.month);
    String seconds(DateTime value) =>
        '${value.toUtc().millisecondsSinceEpoch ~/ 1000}';
    String milliseconds(DateTime value) =>
        '${value.toUtc().millisecondsSinceEpoch}';
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return {
      // Local calendar/time variables. CURRENT_DATE and MONTH_START_DATE use
      // YYYY-MM-DD for request-template substitution.
      'CURRENT_YEAR': '${local.year}',
      'CURRENT_MONTH': '${local.month}',
      'CURRENT_DAY': '${local.day}',
      'CURRENT_DATE': date(local),
      'MONTH_START_DATE': date(localMonthStart),
      'CURRENT_UNIX': seconds(local),
      'CURRENT_UNIX_MS': milliseconds(local),
      // Explicit UTC counterparts avoid dependence on the host time zone.
      'UTC_CURRENT_YEAR': '${utc.year}',
      'UTC_CURRENT_MONTH': '${utc.month}',
      'UTC_CURRENT_DAY': '${utc.day}',
      'UTC_CURRENT_DATE': date(utc),
      'UTC_MONTH_START_DATE': date(utcMonthStart),
      'UTC_CURRENT_UNIX': seconds(utc),
      'UTC_CURRENT_UNIX_MS': milliseconds(utc),
      'DAY_START_UNIX': seconds(localDayStart),
      'DAY_END_UNIX': seconds(localDayEnd),
      'MONTH_START_UNIX': seconds(localMonthStart),
      'MONTH_END_UNIX': seconds(DateTime(local.year, local.month + 1)),
      'DAY_START_UNIX_MS': milliseconds(localDayStart),
      'DAY_END_UNIX_MS': milliseconds(
        localDayEnd.subtract(const Duration(milliseconds: 1)),
      ),
      'MONTH_START_UNIX_MS': milliseconds(localMonthStart),
      'MONTH_TO_DATE_END_UNIX_MS': milliseconds(
        localDayEnd.subtract(const Duration(milliseconds: 1)),
      ),
      'UTC_DAY_START_UNIX': seconds(utcDayStart),
      'UTC_DAY_END_UNIX': seconds(utcDayEnd),
      'UTC_MONTH_START_UNIX': seconds(utcMonthStart),
      'UTC_MONTH_TO_DATE_END_UNIX': seconds(utcDayEnd),
      'TZ_HOURS': '${local.timeZoneOffset.inHours}',
    };
  }
}

class WebBillingFailure implements Exception {
  const WebBillingFailure(this.message);
  final String message;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
