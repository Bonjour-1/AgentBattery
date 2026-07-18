import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/provider_config.dart';
import 'secure_key_store.dart';
import 'web_billing_engine.dart';

class ApiClient {
  ApiClient({
    http.Client? client,
    WebBillingEngine? webBillingEngine,
    ProviderKeyManager? keyManager,
  }) : _client = client ?? http.Client() {
    _webBillingEngine =
        webBillingEngine ??
        WebBillingEngine.withProviderKeyManager(
          keyManager ?? ProviderKeyManager(FlutterSecureKeyStore()),
          transport: (request) async {
            final response = request.method == 'POST'
                ? await _client
                      .post(
                        request.uri,
                        headers: request.headers,
                        body: request.body,
                      )
                      .timeout(_timeout)
                : await _client
                      .get(request.uri, headers: request.headers)
                      .timeout(_timeout);
            return WebBillingHttpResponse(response.statusCode, response.body);
          },
        );
  }

  final http.Client _client;
  late final WebBillingEngine _webBillingEngine;
  static const _timeout = Duration(seconds: 12);

  Future<void> validate(ProviderConfig config) async {
    try {
      final response = await _client
          .get(
            Uri.parse('${config.normalizedBaseUrl}/models'),
            headers: _authorization(config.apiKey),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          '服务返回 ${response.statusCode}',
          safeCategory: 'HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('请求超时', safeCategory: 'timeout');
    } catch (_) {
      throw const ApiException('网络请求失败', safeCategory: 'network');
    }
  }

  Future<BalanceResponse> fetchBalance(ProviderConfig config) =>
      fetchMetrics(config);

  Future<BalanceResponse> fetchMetrics(
    ProviderConfig config, {
    DateTime? now,
  }) async {
    final billingConfig = config.webBillingConfig;
    if (!WebBillingEngine.isExecutable(billingConfig)) {
      throw const ApiException('未配置网页账单请求', safeCategory: 'web-billing');
    }

    final result = await _webBillingEngine.execute(
      providerId: config.id,
      config: billingConfig!,
      now: now,
    );
    if (!result.balance.succeeded || result.balance.value == null) {
      throw ApiException(
        result.balance.failure ?? '账单请求失败',
        safeCategory: 'web-billing',
      );
    }
    return BalanceResponse(
      balance: result.balance.value!,
      dailyUsage: result.daily.value,
      monthlyUsage: result.monthly.value,
      dailyRequested: result.daily.requested,
      monthlyRequested: result.monthly.requested,
      dailySucceeded: result.daily.succeeded,
      monthlySucceeded: result.monthly.succeeded,
      dailyFailure: result.daily.failure,
      monthlyFailure: result.monthly.failure,
    );
  }

  static Map<String, String> _authorization(String key) =>
      key.isEmpty ? const {} : {'Authorization': 'Bearer $key'};
  void close() => _client.close();
}

class BalanceResponse {
  const BalanceResponse({
    required this.balance,
    this.dailyUsage,
    this.monthlyUsage,
    this.dailyRequested = false,
    this.monthlyRequested = false,
    this.dailySucceeded = false,
    this.monthlySucceeded = false,
    this.dailyFailure,
    this.monthlyFailure,
  });
  final double balance;
  final double? dailyUsage;
  final double? monthlyUsage;
  final bool dailyRequested;
  final bool monthlyRequested;
  final bool dailySucceeded;
  final bool monthlySucceeded;
  final String? dailyFailure;
  final String? monthlyFailure;
}

class JsonPathExtractor {
  static final _segment = RegExp(r'([^\.\[\]]+)|\[([0-9]+)\]');
  static final _wildcardSegment = RegExp(
    r'([^\.\[\]]+)(\[\])?|\[([0-9]+)\]|(\[\])',
  );
  static Object? extract(Object? root, String path) {
    if (path.trim().isEmpty) return null;
    Object? value = root;
    var matchedLength = 0;
    for (final match in _segment.allMatches(path)) {
      if (match.start != matchedLength &&
          path.substring(matchedLength, match.start) != '.') {
        return null;
      }
      matchedLength = match.end;
      if (match.group(1) != null) {
        if (value is! Map) return null;
        value = value[match.group(1)];
      } else {
        if (value is! List) return null;
        final index = int.parse(match.group(2)!);
        if (index >= value.length) return null;
        value = value[index];
      }
    }
    return matchedLength == path.length ? value : null;
  }

  static List<Object?>? extractAll(Object? root, String path) {
    if (path.trim().isEmpty) return null;
    var values = <Object?>[root];
    var matchedLength = 0;
    var matchedAny = false;
    var usedWildcard = false;
    for (final match in _wildcardSegment.allMatches(path)) {
      if (match.start != matchedLength &&
          path.substring(matchedLength, match.start) != '.') {
        return null;
      }
      matchedLength = match.end;
      matchedAny = true;
      final next = <Object?>[];
      if (match.group(1) != null) {
        final key = match.group(1)!;
        final wildcard = match.group(2) != null;
        for (final value in values) {
          if (value is! Map || !value.containsKey(key)) return null;
          final nested = value[key];
          if (wildcard) {
            if (nested is! List) return null;
            usedWildcard = true;
            next.addAll(nested);
          } else {
            next.add(nested);
          }
        }
      } else if (match.group(3) != null) {
        final index = int.parse(match.group(3)!);
        for (final value in values) {
          if (value is! List || index >= value.length) return null;
          next.add(value[index]);
        }
      } else {
        for (final value in values) {
          if (value is! List) return null;
          usedWildcard = true;
          next.addAll(value);
        }
      }
      values = next;
    }
    if (!matchedAny || matchedLength != path.length) return null;
    if (!usedWildcard) {
      if (values.length != 1 || values.single is! List) return null;
      return List<Object?>.from(values.single as List);
    }
    return values;
  }
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.safeCategory = 'network',
    this.statusCode,
  });
  final String message;
  final String safeCategory;
  final int? statusCode;
  @override
  String toString() => message;
}
