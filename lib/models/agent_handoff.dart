/// Validation for the non-secret artifact exchanged with a user's Agent.
///
/// This validator deliberately reports paths and error codes only. It never
/// copies request values into diagnostics because those values may be secrets.
class AgentHandoffValidationIssue {
  const AgentHandoffValidationIssue({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  String toString() => '$path [$code] $message';
}

class AgentHandoffValidationResult {
  const AgentHandoffValidationResult(this.issues);

  final List<AgentHandoffValidationIssue> issues;

  bool get isValid => issues.isEmpty;
  String get safeDiagnostics => issues.join('\n');
}

class AgentHandoffValidator {
  const AgentHandoffValidator();

  static final RegExp _identifier = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
  static final RegExp _variableName = RegExp(r'^[A-Z][A-Z0-9_]*$');
  static final RegExp _placeholder = RegExp(r'\$\{([A-Z][A-Z0-9_]*)\}');
  static final RegExp _sensitiveName = RegExp(
    r'(authorization|cookie|api[-_]?key|access[-_]?token|refresh[-_]?token|bearer|token|secret|session)',
    caseSensitive: false,
  );
  static final RegExp _sensitiveBodyField = RegExp(
    r'''["']?(authorization|cookie|api[-_]?key|access[-_]?token|refresh[-_]?token|secret|session)["']?\s*[:=]\s*("[^"]*"|'[^']*'|[^,&}\s]+)''',
    caseSensitive: false,
  );
  static final RegExp _safeProcessingExpression = RegExp(
    r'^\s*(?:(?:sum\(\s*)?\$?[A-Za-z_][A-Za-z0-9_.\[\]*]*(?:\s*\))?|\d+(?:\.\d+)?|[+\-*/()]|\s)+$',
  );

  AgentHandoffValidationResult validate(Object? raw) {
    final issues = <AgentHandoffValidationIssue>[];
    final artifact = _map(raw);
    if (artifact == null) {
      _add(issues, 'artifact_type', r'$', 'Artifact must be a JSON object.');
      return AgentHandoffValidationResult(issues);
    }

    if (artifact['schema_version'] != '1.0') {
      _add(
        issues,
        'schema_version',
        r'$.schema_version',
        'Only schema version 1.0 is supported.',
      );
    }
    final action = artifact['action'];
    if (action != 'configure_web_billing' && action != 'renew_credentials') {
      _add(issues, 'action', r'$.action', 'Action is not supported.');
    }

    final provider = _map(artifact['provider']);
    final providerId = provider?['id'];
    if (providerId is! String || !_identifier.hasMatch(providerId)) {
      _add(issues, 'provider_id', r'$.provider.id', 'Provider id is invalid.');
    }
    final baseUrl = provider?['base_url'];
    if (baseUrl != null && (baseUrl is! String || !_isHttpTemplate(baseUrl))) {
      _add(
        issues,
        'provider_url',
        r'$.provider.base_url',
        'Provider base URL must use HTTP or HTTPS.',
      );
    }

    final secretNames = <String>{};
    final secrets = _list(artifact['secret_variables']);
    for (var index = 0; index < secrets.length; index++) {
      final secret = _map(secrets[index]);
      final name = secret?['name'];
      final path =
          r'$.secret_variables['
          '$index].name';
      if (name is! String || !_variableName.hasMatch(name)) {
        _add(issues, 'secret_name', path, 'Secret variable name is invalid.');
      } else if (!secretNames.add(name)) {
        _add(
          issues,
          'duplicate_secret_name',
          path,
          'Secret variable name must be unique.',
        );
      }
      if (secret != null && secret.containsKey('value')) {
        _add(
          issues,
          'secret_value_forbidden',
          r'$.secret_variables['
              '$index].value',
          'Secret values are forbidden in artifacts.',
        );
      }
    }

    final requestIds = <String>{};
    final requests = _list(artifact['request_templates']);
    for (var index = 0; index < requests.length; index++) {
      final request = _map(requests[index]);
      final root =
          r'$.request_templates['
          '$index]';
      final id = request?['id'];
      if (id is! String || !_identifier.hasMatch(id)) {
        _add(issues, 'request_id', '$root.id', 'Request id is invalid.');
      } else if (!requestIds.add(id)) {
        _add(
          issues,
          'duplicate_request_id',
          '$root.id',
          'Request id must be unique.',
        );
      }

      final method = request?['method'];
      if (method != 'GET' && method != 'POST') {
        _add(
          issues,
          'method',
          '$root.method',
          'Only GET and POST are supported.',
        );
      }
      final url = request?['url_template'];
      if (url is! String || !_isHttpTemplate(url)) {
        _add(
          issues,
          'url',
          '$root.url_template',
          'Request URL must use HTTP or HTTPS.',
        );
      }

      _validateRequestSecrets(
        issues: issues,
        request: request,
        root: root,
        secretNames: secretNames,
      );
    }

    final metrics = _list(artifact['metric_rules']);
    if (metrics.isEmpty) {
      _add(
        issues,
        'metric_required',
        r'$.metric_rules',
        'At least one metric rule is required.',
      );
    }
    final metricIds = <String>{};
    for (var index = 0; index < metrics.length; index++) {
      final metric = _map(metrics[index]);
      final root =
          r'$.metric_rules['
          '$index]';
      final id = metric?['id'];
      if (id is! String || !_identifier.hasMatch(id)) {
        _add(issues, 'metric_id', '$root.id', 'Metric id is invalid.');
      } else if (!metricIds.add(id)) {
        _add(
          issues,
          'duplicate_metric_id',
          '$root.id',
          'Metric id must be unique.',
        );
      }
      if (!const {'balance', 'daily', 'monthly'}.contains(metric?['kind'])) {
        _add(
          issues,
          'metric_kind',
          '$root.kind',
          'Metric kind is not supported.',
        );
      }
      if (!requestIds.contains(metric?['request_template_id'])) {
        _add(
          issues,
          'request_reference',
          '$root.request_template_id',
          'Metric references an unknown request.',
        );
      }
      final responsePath = metric?['response_path'];
      final expression = metric?['processing_expression'];
      final validPath =
          responsePath is String &&
          responsePath.startsWith(r'$.') &&
          responsePath.length > 2;
      final validExpression =
          expression is String && expression.trim().isNotEmpty;
      if (validExpression && !_safeProcessingExpression.hasMatch(expression)) {
        _add(
          issues,
          'processing_expression',
          '$root.processing_expression',
          'Processing expression contains unsupported syntax.',
        );
      }
      if (!validPath && !validExpression) {
        _add(
          issues,
          'response_path',
          '$root.response_path',
          'A JSON response path or processing expression is required.',
        );
      }
      _validatePositiveNumber(
        issues,
        metric?['multiplier'],
        '$root.multiplier',
        'multiplier',
      );
      _validatePositiveNumber(
        issues,
        metric?['divisor'],
        '$root.divisor',
        'divisor',
      );
    }

    if (action == 'renew_credentials') {
      _validateRenewal(issues, artifact['credential_renewal'], secretNames);
    }

    return AgentHandoffValidationResult(List.unmodifiable(issues));
  }

  void _validateRequestSecrets({
    required List<AgentHandoffValidationIssue> issues,
    required Map<String, Object?>? request,
    required String root,
    required Set<String> secretNames,
  }) {
    if (request == null) return;
    final fields = <String, String>{};
    final url = request['url_template'];
    if (url is String) fields['$root.url_template'] = url;
    final body = request['body_template'];
    if (body is String) fields['$root.body_template'] = body;
    for (final entry in _stringMap(request['headers_template']).entries) {
      final path = '$root.headers_template.${entry.key}';
      fields[path] = entry.value;
      if (_sensitiveName.hasMatch(entry.key) &&
          !_isExactlyPlaceholderTemplate(entry.value)) {
        _add(
          issues,
          'secret_literal_header',
          path,
          'Sensitive header values must use a variable placeholder.',
        );
      }
    }
    for (final entry in _stringMap(request['query_template']).entries) {
      final path = '$root.query_template.${entry.key}';
      fields[path] = entry.value;
      if (_sensitiveName.hasMatch(entry.key) &&
          !_isExactlyPlaceholderTemplate(entry.value)) {
        _add(
          issues,
          'secret_literal_query',
          path,
          'Sensitive query values must use a variable placeholder.',
        );
      }
    }

    if (url is String) {
      for (final pair in _queryPairs(url)) {
        if (_sensitiveName.hasMatch(pair.key) &&
            !_isExactlyPlaceholderTemplate(pair.value)) {
          _add(
            issues,
            'secret_literal_url',
            '$root.url_template',
            'Sensitive URL values must use a variable placeholder.',
          );
          break;
        }
      }
    }
    if (body is String) {
      for (final match in _sensitiveBodyField.allMatches(body)) {
        final captured = match.group(2) ?? '';
        final value =
            captured.length >= 2 &&
                ((captured.startsWith('"') && captured.endsWith('"')) ||
                    (captured.startsWith("'") && captured.endsWith("'")))
            ? captured.substring(1, captured.length - 1)
            : captured;
        if (!_isExactlyPlaceholderTemplate(value)) {
          _add(
            issues,
            'secret_literal_body',
            '$root.body_template',
            'Sensitive body values must use a variable placeholder.',
          );
          break;
        }
      }
    }

    for (final field in fields.entries) {
      for (final match in _placeholder.allMatches(field.value)) {
        final name = match.group(1)!;
        if (!secretNames.contains(name) && !_isRuntimeVariable(name)) {
          _add(
            issues,
            'undeclared_variable',
            field.key,
            'Request uses an undeclared variable placeholder.',
          );
        }
      }
    }
  }

  void _validateRenewal(
    List<AgentHandoffValidationIssue> issues,
    Object? raw,
    Set<String> secretNames,
  ) {
    final renewal = _map(raw);
    if (renewal == null) {
      _add(
        issues,
        'credential_renewal',
        r'$.credential_renewal',
        'Credential renewal details are required.',
      );
      return;
    }
    if (renewal['preserve_billing_rules'] != true) {
      _add(
        issues,
        'preserve_billing_rules',
        r'$.credential_renewal.preserve_billing_rules',
        'Credential renewal must preserve billing rules.',
      );
    }
    final required = _list(renewal['required_variables']);
    if (required.isEmpty) {
      _add(
        issues,
        'renewal_variable',
        r'$.credential_renewal.required_variables',
        'At least one credential variable is required.',
      );
    }
    for (var index = 0; index < required.length; index++) {
      if (required[index] is! String ||
          !secretNames.contains(required[index])) {
        _add(
          issues,
          'renewal_variable',
          r'$.credential_renewal.required_variables['
              '$index]',
          'Renewal references an unknown secret variable.',
        );
      }
    }
  }

  static void _validatePositiveNumber(
    List<AgentHandoffValidationIssue> issues,
    Object? value,
    String path,
    String code,
  ) {
    if (value is! num || !value.isFinite || value <= 0) {
      _add(
        issues,
        code,
        path,
        'Value must be a finite number greater than zero.',
      );
    }
  }

  static bool _isHttpTemplate(String value) {
    final normalized = value.replaceAll(_placeholder, 'placeholder');
    final uri = Uri.tryParse(normalized);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _isExactlyPlaceholderTemplate(String value) {
    final matches = _placeholder.allMatches(value).toList();
    if (matches.length != 1) return false;
    final remainder = value.replaceRange(
      matches.single.start,
      matches.single.end,
      '',
    );
    return remainder.trim().isEmpty ||
        RegExp(
          r'^(Bearer|session=)$',
          caseSensitive: false,
        ).hasMatch(remainder.trim());
  }

  static const _runtimeVariables = {
    'CURRENT_YEAR',
    'CURRENT_MONTH',
    'CURRENT_DAY',
    'CURRENT_DATE',
    'MONTH_START_DATE',
    'CURRENT_UNIX',
    'CURRENT_UNIX_MS',
    'UTC_CURRENT_YEAR',
    'UTC_CURRENT_MONTH',
    'UTC_CURRENT_DAY',
    'UTC_CURRENT_DATE',
    'UTC_MONTH_START_DATE',
    'UTC_CURRENT_UNIX',
    'UTC_CURRENT_UNIX_MS',
    'DAY_START_UNIX',
    'DAY_END_UNIX',
    'MONTH_START_UNIX',
    'MONTH_END_UNIX',
    'DAY_START_UNIX_MS',
    'DAY_END_UNIX_MS',
    'MONTH_START_UNIX_MS',
    'MONTH_TO_DATE_END_UNIX_MS',
    'UTC_DAY_START_UNIX',
    'UTC_DAY_END_UNIX',
    'UTC_MONTH_START_UNIX',
    'UTC_MONTH_TO_DATE_END_UNIX',
    'TZ_HOURS',
  };

  static bool _isRuntimeVariable(String name) =>
      _runtimeVariables.contains(name);

  static Iterable<MapEntry<String, String>> _queryPairs(String url) sync* {
    final queryIndex = url.indexOf('?');
    if (queryIndex < 0) return;
    for (final part in url.substring(queryIndex + 1).split('&')) {
      final separator = part.indexOf('=');
      if (separator < 0) continue;
      yield MapEntry(
        part.substring(0, separator),
        part.substring(separator + 1),
      );
    }
  }

  static Map<String, Object?>? _map(Object? value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : null;

  static List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : const [];

  static Map<String, String> _stringMap(Object? value) {
    final map = _map(value);
    if (map == null) return const {};
    return map.map((key, value) => MapEntry(key, value.toString()));
  }

  static void _add(
    List<AgentHandoffValidationIssue> issues,
    String code,
    String path,
    String message,
  ) {
    issues.add(
      AgentHandoffValidationIssue(code: code, path: path, message: message),
    );
  }
}
