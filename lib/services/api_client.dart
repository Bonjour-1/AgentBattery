import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/provider_config.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _timeout = Duration(seconds: 12);

  Future<void> validate(ProviderConfig config) async {
    final response = await _client
        .get(
          Uri.parse('${config.normalizedBaseUrl}/models'),
          headers: _authorization(config.apiKey),
        )
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('服务返回 ${response.statusCode}');
    }
  }

  Future<BalanceResponse> fetchBalance(ProviderConfig config) async {
    if (!config.advancedEnabled ||
        config.balanceUrl.trim().isEmpty ||
        config.balanceJsonPath.trim().isEmpty) {
      throw const ApiException('余额不可查询');
    }
    final headers = _authorization(
      config.balanceToken.isEmpty ? config.apiKey : config.balanceToken,
    );
    try {
      final decodedHeaders = jsonDecode(
        config.balanceHeaders.isEmpty ? '{}' : config.balanceHeaders,
      );
      if (decodedHeaders is! Map) throw const FormatException();
      for (final entry in decodedHeaders.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    } catch (_) {
      throw const ApiException('自定义 Headers JSON 格式错误');
    }
    final uri = _resolveUrl(config.normalizedBaseUrl, config.balanceUrl);
    http.Response response;
    if (config.balanceMethod == BalanceRequestMethod.post) {
      String? body;
      if (config.balanceBody.trim().isNotEmpty) {
        try {
          jsonDecode(config.balanceBody);
        } catch (_) {
          throw const ApiException('请求体 JSON 格式错误');
        }
        body = config.balanceBody.replaceAll(
          r'${API_KEY}',
          config.balanceToken.isEmpty ? config.apiKey : config.balanceToken,
        );
        headers.putIfAbsent('Content-Type', () => 'application/json');
      }
      response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(_timeout);
    } else {
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('服务返回 ${response.statusCode}');
    }
    try {
      final root = jsonDecode(response.body);
      final balance = _number(
        JsonPathExtractor.extract(root, config.balanceJsonPath),
      );
      if (balance == null || !balance.isFinite) throw const FormatException();
      return BalanceResponse(
        balance: balance,
        dailyUsage: _number(
          JsonPathExtractor.extract(root, config.dailyUsageJsonPath),
        ),
        monthlyUsage: _number(
          JsonPathExtractor.extract(root, config.monthlyUsageJsonPath),
        ),
      );
    } catch (_) {
      throw const ApiException('余额数据格式异常');
    }
  }

  static Map<String, String> _authorization(String key) =>
      key.isEmpty ? {} : {'Authorization': 'Bearer $key'};
  static Uri _resolveUrl(String baseUrl, String balanceUrl) =>
      Uri.tryParse(balanceUrl)?.hasScheme == true
      ? Uri.parse(balanceUrl)
      : Uri.parse(baseUrl).resolve(
          balanceUrl.startsWith('/') ? balanceUrl.substring(1) : balanceUrl,
        );
  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  void close() => _client.close();
}

class BalanceResponse {
  const BalanceResponse({
    required this.balance,
    this.dailyUsage,
    this.monthlyUsage,
  });
  final double balance;
  final double? dailyUsage;
  final double? monthlyUsage;
}

class JsonPathExtractor {
  static final _segment = RegExp(r'([^.\[\]]+)|\[([0-9]+)\]');
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
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
