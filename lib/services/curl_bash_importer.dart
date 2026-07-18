import 'dart:convert';

import 'package:agent_battery_flutter/models/web_billing_config.dart';

/// Parses a deliberately small, non-executing subset of browser Copy as cURL
/// bash output. It never invokes a shell or makes a network request.
class CurlBashImporter {
  const CurlBashImporter();

  CurlParseResult parse(String source) {
    final unsafe = _unsupportedSyntax(source);
    if (unsafe != null) return CurlParseResult.failure(unsafe);

    late final List<String> tokens;
    try {
      tokens = _shellWords(source.replaceAll(RegExp(r'\\\r?\n'), ''));
    } on FormatException catch (error) {
      return CurlParseResult.failure(error.message);
    }
    if (tokens.isEmpty || tokens.first != 'curl') {
      return CurlParseResult.failure(
        'Only a leading curl command is supported.',
      );
    }

    String? url;
    String? explicitMethod;
    String? body;
    final headers = <String, String>{};
    String? cookie;

    try {
      for (var index = 1; index < tokens.length; index++) {
        final token = tokens[index];
        String argument() {
          if (++index >= tokens.length) {
            throw const FormatException('A curl option is missing its value.');
          }
          return tokens[index];
        }

        switch (token) {
          case '-X':
          case '--request':
            explicitMethod = argument().toUpperCase();
          case '-H':
          case '--header':
            final header = argument();
            final separator = header.indexOf(':');
            if (separator <= 0) {
              throw const FormatException(
                'A header must use Name: Value syntax.',
              );
            }
            headers[header.substring(0, separator).trim()] = header
                .substring(separator + 1)
                .trimLeft();
          case '-b':
          case '--cookie':
            cookie = argument();
          case '-d':
          case '--data':
          case '--data-raw':
          case '--data-binary':
            if (body != null) {
              throw const FormatException(
                'Only one request body option is supported.',
              );
            }
            body = argument();
          default:
            if (token.startsWith('-')) {
              throw FormatException('Unsupported curl option: $token');
            }
            if (url != null) {
              throw const FormatException('Only one URL is supported.');
            }
            url = token;
        }
      }
    } on FormatException catch (error) {
      return CurlParseResult.failure(error.message);
    }

    if (url == null || url.isEmpty) {
      return CurlParseResult.failure('A curl URL is required.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return CurlParseResult.failure(
        'The curl URL must be an absolute HTTP URL.',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return CurlParseResult.failure('Only HTTP and HTTPS URLs are supported.');
    }

    final secrets = _SecretCollector();
    final query = <String, String>{};
    for (final pair in uri.query.split('&')) {
      if (pair.isEmpty) continue;
      final equals = pair.indexOf('=');
      final encodedKey = equals < 0 ? pair : pair.substring(0, equals);
      final encodedValue = equals < 0 ? '' : pair.substring(equals + 1);
      final key = Uri.decodeQueryComponent(encodedKey);
      final value = Uri.decodeQueryComponent(encodedValue);
      query[key] = _isSensitiveKey(key)
          ? secrets.replace(
              value,
              _keyVariableBase(key),
              SecretVariableType.genericBodyValue,
            )
          : value;
    }

    final templateHeaders = <String, String>{};
    for (final entry in headers.entries) {
      final lowerName = entry.key.toLowerCase();
      if (lowerName == 'authorization' &&
          entry.value.toLowerCase().startsWith('bearer ') &&
          entry.value.length > 'Bearer '.length) {
        final prefix = entry.value.substring(0, entry.value.indexOf(' ') + 1);
        final value = entry.value.substring(prefix.length);
        templateHeaders[entry.key] =
            '$prefix${secrets.replace(value, 'AUTHORIZATION_TOKEN', SecretVariableType.bearerToken)}';
      } else if (_sensitiveHeaderNames.contains(lowerName)) {
        templateHeaders[entry.key] = secrets.replace(
          entry.value,
          _headerVariableBase(lowerName),
          _headerVariableType(lowerName),
        );
      } else {
        templateHeaders[entry.key] = entry.value;
      }
    }
    if (cookie != null) {
      templateHeaders.removeWhere((key, _) => key.toLowerCase() == 'cookie');
      templateHeaders['Cookie'] = secrets.replace(
        cookie,
        'COOKIE',
        SecretVariableType.cookieHeader,
      );
    }

    final templateBody = body == null
        ? null
        : _replaceJsonSecrets(body, secrets);
    final baseUri = _uriWithoutQueryAndFragment(uri);
    final request = RequestTemplate(
      id: 'imported-request',
      method: explicitMethod ?? (body == null ? 'GET' : 'POST'),
      urlTemplate: baseUri.toString(),
      queryTemplate: query,
      headersTemplate: templateHeaders,
      bodyTemplate: templateBody,
    );
    return CurlParseResult.success(
      CurlImportDraft(
        requestTemplate: request,
        secretVariableDefinitions: secrets.definitions,
      ),
      secrets.candidates,
    );
  }
}

/// Persistent, JSON-safe import result. Secret values are intentionally absent.
class CurlImportDraft {
  const CurlImportDraft({
    required this.requestTemplate,
    required this.secretVariableDefinitions,
  });

  final RequestTemplate requestTemplate;
  final List<SecretVariableDefinition> secretVariableDefinitions;

  Map<String, Object?> toJson() => {
    'request_template': requestTemplate.toJson(),
    'secret_variable_definitions': secretVariableDefinitions
        .map((definition) => definition.toJson())
        .toList(),
  };
}

/// Memory-only candidate for the caller to send to secure storage after consent.
/// This type deliberately provides no JSON serialization API.
class SecretValueCandidate {
  const SecretValueCandidate({required this.variableName, required this.value});

  final String variableName;

  /// Ephemeral plaintext for explicit, consented secure-storage persistence.
  /// Never log, serialize, or interpolate this value into diagnostics.
  final String value;

  /// Safe representation for UI and diagnostic contexts.
  String get maskedValue => '[REDACTED]';

  @override
  String toString() =>
      'SecretValueCandidate(variableName: $variableName, value: $maskedValue)';
}

class CurlParseResult {
  const CurlParseResult._({
    this.draft,
    this.secretValueCandidates = const [],
    this.error,
  });

  factory CurlParseResult.success(
    CurlImportDraft draft,
    List<SecretValueCandidate> candidates,
  ) => CurlParseResult._(draft: draft, secretValueCandidates: candidates);

  factory CurlParseResult.failure(String error) =>
      CurlParseResult._(error: error);

  final CurlImportDraft? draft;
  final List<SecretValueCandidate> secretValueCandidates;
  final String? error;
}

const _sensitiveHeaderNames = <String>{
  'authorization',
  'cookie',
  'x-api-key',
  'api-key',
  'x-subject-id',
};
const _sensitiveKeys = <String>{
  'token',
  'api_key',
  'apikey',
  'key',
  'api-key',
  'x-api-key',
  'access_token',
  'session',
};

bool _isSensitiveKey(String key) => _sensitiveKeys.contains(key.toLowerCase());

String _keyVariableBase(String key) => switch (key.toLowerCase()) {
  'key' || 'api_key' || 'apikey' || 'api-key' || 'x-api-key' => 'API_KEY',
  _ => _upperSnake(key),
};

String _headerVariableBase(String lowerName) => switch (lowerName) {
  'authorization' => 'AUTHORIZATION_TOKEN',
  'cookie' => 'COOKIE',
  'x-api-key' || 'api-key' => 'API_KEY',
  'x-subject-id' => 'SUBJECT_ID',
  _ => _upperSnake(lowerName),
};

SecretVariableType _headerVariableType(String lowerName) => switch (lowerName) {
  'authorization' => SecretVariableType.bearerToken,
  'cookie' => SecretVariableType.cookieHeader,
  'x-subject-id' => SecretVariableType.subjectId,
  _ => SecretVariableType.genericHeaderValue,
};

String _upperSnake(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match[1]}_${match[2]}',
    )
    .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '')
    .toUpperCase();

String _uriWithoutQueryAndFragment(Uri uri) {
  final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  return '${uri.scheme}://$authority${uri.path}';
}

String _replaceJsonSecrets(String body, _SecretCollector secrets) {
  try {
    final decoded = jsonDecode(body);
    final replaced = _replaceJsonValue(decoded, secrets);
    return jsonEncode(replaced);
  } on FormatException {
    return body;
  }
}

Object? _replaceJsonValue(
  Object? value,
  _SecretCollector secrets, [
  String? key,
]) {
  if (value is Map) {
    return value.map<String, Object?>((rawKey, rawValue) {
      final mapKey = rawKey.toString();
      if (_isSensitiveKey(mapKey) && rawValue is String) {
        return MapEntry(
          mapKey,
          secrets.replace(
            rawValue,
            _keyVariableBase(mapKey),
            SecretVariableType.genericBodyValue,
          ),
        );
      }
      return MapEntry(mapKey, _replaceJsonValue(rawValue, secrets, mapKey));
    });
  }
  if (value is List) {
    return value.map((item) => _replaceJsonValue(item, secrets, key)).toList();
  }
  return value;
}

class _SecretCollector {
  final _definitions = <SecretVariableDefinition>[];
  final _candidates = <SecretValueCandidate>[];
  final _usedNames = <String>{};
  final _namesByValueAndPreferredName = <(String, String), String>{};

  List<SecretVariableDefinition> get definitions =>
      List.unmodifiable(_definitions);
  List<SecretValueCandidate> get candidates => List.unmodifiable(_candidates);

  String replace(String value, String preferredName, SecretVariableType type) {
    final reuseKey = (value, preferredName);
    final existingName = _namesByValueAndPreferredName[reuseKey];
    if (existingName != null) return '\${$existingName}';
    var name = preferredName;
    var suffix = 2;
    while (!_usedNames.add(name)) {
      name = '${preferredName}_$suffix';
      suffix++;
    }
    _definitions.add(
      SecretVariableDefinition(
        id: name.toLowerCase(),
        name: name,
        displayName: name.replaceAll('_', ' '),
        type: type,
        required: true,
      ),
    );
    _candidates.add(SecretValueCandidate(variableName: name, value: value));
    _namesByValueAndPreferredName[reuseKey] = name;
    return '\${$name}';
  }
}

String? _unsupportedSyntax(String source) {
  final unquoted = StringBuffer();
  final expansionContext = StringBuffer();
  var quote = '';
  for (var index = 0; index < source.length; index++) {
    final character = source[index];
    if (quote.isNotEmpty) {
      if (character == quote) {
        quote = '';
      } else if (quote != "'") {
        expansionContext.write(character);
      }
      continue;
    }
    if (character == "'" || character == '"') {
      quote = character;
    } else if (character == '\\' && index + 1 < source.length) {
      unquoted.write(character);
      unquoted.write(source[++index]);
      expansionContext.write(character);
      expansionContext.write(source[index]);
    } else {
      unquoted.write(character);
      expansionContext.write(character);
    }
  }
  if (RegExp(r'`|\$\(').hasMatch(expansionContext.toString())) {
    return 'Unsupported shell syntax in cURL input.';
  }
  final patterns = <RegExp>[
    RegExp(r'`'),
    RegExp(r'\$\('),
    RegExp(r'\|'),
    RegExp(r'(?<!\\)[;]'),
    RegExp(r'(?<!\\)(?:>>?|<)'),
    RegExp(r'<\('),
    RegExp(r'>\('),
  ];
  return patterns.any((pattern) => pattern.hasMatch(unquoted.toString()))
      ? 'Unsupported shell syntax in cURL input.'
      : null;
}

List<String> _shellWords(String source) {
  final words = <String>[];
  final buffer = StringBuffer();
  var quoted = '';
  var started = false;
  for (var index = 0; index < source.length; index++) {
    final character = source[index];
    if (quoted.isNotEmpty) {
      if (character == quoted) {
        quoted = '';
      } else if (quoted == '"' &&
          character == '\\' &&
          index + 1 < source.length) {
        buffer.write(source[++index]);
      } else {
        buffer.write(character);
      }
      started = true;
      continue;
    }
    if (character == "'" || character == '"') {
      quoted = character;
      started = true;
    } else if (character == '\\') {
      if (++index >= source.length) {
        throw const FormatException('Trailing escape in cURL input.');
      }
      buffer.write(source[index]);
      started = true;
    } else if (character.trim().isEmpty) {
      if (started) {
        words.add(buffer.toString());
        buffer.clear();
        started = false;
      }
    } else {
      buffer.write(character);
      started = true;
    }
  }
  if (quoted.isNotEmpty) {
    throw const FormatException('Unterminated quote in cURL input.');
  }
  if (started) words.add(buffer.toString());
  return words;
}
