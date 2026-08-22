import '../models/agent_handoff.dart';
import '../models/provider_config.dart';
import '../models/web_billing_config.dart';
import 'storage_service.dart';

class AgentHandoffImportException implements Exception {
  const AgentHandoffImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AgentHandoffImportResult {
  const AgentHandoffImportResult({
    required this.providerId,
    required this.configuredMetrics,
    required this.renewalOnly,
  });

  final String providerId;
  final List<String> configuredMetrics;
  final bool renewalOnly;
}

class AgentHandoffImporter {
  const AgentHandoffImporter(this._storage);

  final StorageService _storage;

  Future<AgentHandoffImportResult> import(
    Object? raw, {
    required Map<String, String> secretValues,
  }) async {
    final validation = const AgentHandoffValidator().validate(raw);
    if (!validation.isValid) {
      throw AgentHandoffImportException(
        'Artifact validation failed (${validation.issues.length} issue(s)).',
      );
    }
    final artifact = Map<String, Object?>.from(raw! as Map);
    final provider = Map<String, Object?>.from(artifact['provider']! as Map);
    final providerId = provider['id']! as String;
    final definitions = _definitions(artifact['secret_variables']);
    final declared = definitions.map((item) => item.name).toSet();
    final supplied = secretValues.keys.toSet();
    final undeclared = supplied.difference(declared).toList()..sort();
    if (undeclared.isNotEmpty) {
      throw AgentHandoffImportException(
        'Undeclared secret variable(s): ${undeclared.join(', ')}.',
      );
    }
    final action = artifact['action']! as String;
    final requiredNames = action == 'renew_credentials'
        ? (Map<String, Object?>.from(
                    artifact['credential_renewal']! as Map,
                  )['required_variables']!
                  as List)
              .cast<String>()
              .toSet()
        : definitions
              .where((item) => item.required)
              .map((item) => item.name)
              .toSet();
    final required =
        requiredNames
            .where((name) => secretValues[name]?.isNotEmpty != true)
            .toList()
          ..sort();
    if (required.isNotEmpty) {
      throw AgentHandoffImportException(
        'Required secret variable(s) missing: ${required.join(', ')}.',
      );
    }

    if (action == 'renew_credentials') {
      final snapshot = await _storage.load();
      final existing = snapshot.providerConfigs
          .where((config) => config.id == providerId)
          .firstOrNull;
      if (existing == null) {
        throw const AgentHandoffImportException(
          'Credential renewal requires an existing provider.',
        );
      }
      final existingNames =
          existing.webBillingConfig?.secretVariableDefinitions
              .map((item) => item.name)
              .toSet() ??
          const <String>{};
      if (!existingNames.containsAll(supplied)) {
        throw const AgentHandoffImportException(
          'Credential renewal contains an unknown variable.',
        );
      }
      await _writeSecretsWithRollback(providerId, secretValues);
      return AgentHandoffImportResult(
        providerId: providerId,
        configuredMetrics:
            existing.webBillingConfig?.metricRules
                .map((item) => item.kind.name)
                .toSet()
                .toList() ??
            const [],
        renewalOnly: true,
      );
    }

    final snapshot = await _storage.load();
    final webBilling = _webBillingConfig(artifact, definitions);
    final existingIndex = snapshot.providerConfigs.indexWhere(
      (config) => config.id == providerId,
    );
    final existing = existingIndex < 0
        ? null
        : snapshot.providerConfigs[existingIndex];
    final config = ProviderConfig(
      id: providerId,
      name: provider['name']! as String,
      colorValue: existing?.colorValue ?? 0xff39c5bb,
      order: existing?.order ?? snapshot.providerConfigs.length,
      enabled: existing?.enabled ?? true,
      baseUrl: provider['base_url']?.toString() ?? existing?.baseUrl ?? '',
      defaultModel: existing?.defaultModel ?? '',
      rechargeUrl: existing?.rechargeUrl ?? '',
      lowBalanceThreshold: existing?.lowBalanceThreshold,
      webBillingConfig: webBilling,
    );

    final originals = await _writeSecretsWithRollback(providerId, secretValues);
    try {
      final configs = snapshot.providerConfigs.toList();
      if (existingIndex < 0) {
        configs.add(config);
      } else {
        configs[existingIndex] = config;
      }
      await _storage.save(snapshot.copyWith(providerConfigs: configs));
    } catch (_) {
      final rollbackComplete = await _restoreSecrets(providerId, originals);
      if (!rollbackComplete) {
        throw const AgentHandoffImportException(
          'Provider configuration save failed and credential rollback failed.',
        );
      }
      throw const AgentHandoffImportException(
        'Provider configuration was not saved.',
      );
    }
    return AgentHandoffImportResult(
      providerId: providerId,
      configuredMetrics: webBilling.metricRules
          .map((item) => item.kind.name)
          .toSet()
          .toList(),
      renewalOnly: false,
    );
  }

  Future<Map<String, String?>> _writeSecretsWithRollback(
    String providerId,
    Map<String, String> values,
  ) async {
    final originals = await _readSecrets(providerId, values.keys);
    try {
      for (final entry in values.entries) {
        await _storage.saveProviderWebBillingVariables(providerId, {
          entry.key: entry.value,
        });
      }
      return originals;
    } catch (_) {
      final rollbackComplete = await _restoreSecrets(providerId, originals);
      if (!rollbackComplete) {
        throw const AgentHandoffImportException(
          'Secure credential write failed and rollback failed.',
        );
      }
      throw const AgentHandoffImportException(
        'Secure credential write failed.',
      );
    }
  }

  Future<Map<String, String?>> _readSecrets(
    String providerId,
    Iterable<String> names,
  ) async {
    final result = <String, String?>{};
    for (final name in names) {
      result[name] = await _storage.readScopedProviderWebBillingVariable(
        providerId,
        name,
      );
    }
    return result;
  }

  Future<bool> _restoreSecrets(
    String providerId,
    Map<String, String?> originals,
  ) async {
    var complete = true;
    for (final entry in originals.entries) {
      try {
        if (entry.value == null) {
          await _storage.deleteProviderWebBillingVariable(
            providerId,
            entry.key,
          );
        } else {
          await _storage.saveProviderWebBillingVariables(providerId, {
            entry.key: entry.value!,
          });
        }
      } catch (_) {
        complete = false;
      }
    }
    return complete;
  }

  List<SecretVariableDefinition> _definitions(Object? raw) => (raw as List)
      .map((item) => Map<String, Object?>.from(item as Map))
      .map(
        (item) => SecretVariableDefinition(
          id: item['name']! as String,
          name: item['name']! as String,
          displayName: item['display_name']! as String,
          type: SecretVariableType.values.firstWhere(
            (value) => _snakeCase(value.name) == item['type'],
          ),
          required: item['required']! as bool,
        ),
      )
      .toList();

  WebBillingConfig _webBillingConfig(
    Map<String, Object?> artifact,
    List<SecretVariableDefinition> definitions,
  ) {
    final requests = (artifact['request_templates']! as List)
        .map((item) => Map<String, Object?>.from(item as Map))
        .map(
          (item) => RequestTemplate(
            id: item['id']! as String,
            method: item['method']! as String,
            urlTemplate: item['url_template']! as String,
            queryTemplate: _stringMap(item['query_template']),
            headersTemplate: _stringMap(item['headers_template']),
            bodyTemplate: item['body_template']?.toString(),
          ),
        )
        .toList();
    final metrics = (artifact['metric_rules']! as List)
        .map((item) => Map<String, Object?>.from(item as Map))
        .map(
          (item) => MetricRule(
            id: item['id']! as String,
            kind: WebBillingMetricKind.values.firstWhere(
              (value) => value.name == item['kind'],
            ),
            requestTemplateId: item['request_template_id']! as String,
            responseRule: ResponseRule(
              scalarPath: _runtimePath(item['response_path']?.toString() ?? ''),
            ),
            processingExpression: item['processing_expression']?.toString(),
            multiplier: (item['multiplier'] as num).toDouble(),
            divisor: (item['divisor'] as num).toDouble(),
            unit: item.containsKey('unit') ? item['unit']?.toString() : '元',
          ),
        )
        .toList();
    return WebBillingConfig(
      schemaVersion: 1,
      source: 'agent_handoff',
      requestTemplates: requests,
      secretVariableDefinitions: definitions,
      metricRules: metrics,
      credentialRefresh: _credentialRefresh(artifact['credential_refresh']),
    );
  }

  CredentialRefreshConfig? _credentialRefresh(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final request = Map<String, Object?>.from(json['request_template']! as Map);
    return CredentialRefreshConfig(
      triggerStatusCodes: (json['trigger_status_codes']! as List)
          .cast<num>()
          .map((value) => value.toInt())
          .toList(),
      requestTemplate: RequestTemplate.fromJson(request),
      responseVariablePaths: _stringMap(json['response_variable_paths']),
    );
  }

  Map<String, String> _stringMap(Object? raw) => raw is Map
      ? raw.map((key, value) => MapEntry(key.toString(), value.toString()))
      : const {};

  String _runtimePath(String path) =>
      path.startsWith(r'$.') ? path.substring(2) : path;

  String _snakeCase(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
}
