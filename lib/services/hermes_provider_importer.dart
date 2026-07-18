import 'dart:io';

import '../models/provider_config.dart';

/// Imports Hermes provider connection metadata and model API keys only.
///
/// Web-billing configuration, its secrets, request templates, and provider
/// runtime state are deliberately outside this import boundary.
class HermesProviderImporter {
  const HermesProviderImporter();

  static const windowsConfigPath =
      r'\\wsl.localhost\Linux\root\.hermes\config.yaml';
  static const windowsEnvPath = r'\\wsl.localhost\Linux\root\.hermes\.env';

  Future<HermesImportPlan> readDefaultFiles() async {
    if (!Platform.isWindows) {
      throw const HermesImportException('此导入功能仅可在 Windows 上读取 WSL Hermes 配置。');
    }
    try {
      final config = await File(windowsConfigPath).readAsString();
      String env = '';
      try {
        env = await File(windowsEnvPath).readAsString();
      } on FileSystemException {
        // A .env file is optional. Inline API keys still remain importable.
      }
      return parse(configYaml: config, envFile: env);
    } on FileSystemException {
      throw const HermesImportException(
        '无法读取 WSL Hermes 配置。请确认 WSL 已启动且 \\wsl.localhost\\Linux 可访问。',
      );
    }
  }

  HermesImportPlan parse({required String configYaml, String envFile = ''}) {
    final env = _parseEnv(envFile);
    final usedIds = <String>{};
    final providers = [
      ..._parseProviders(configYaml, env, usedIds),
      ..._parseCustomProviders(configYaml, env, usedIds),
    ];
    if (!_hasExplicitDeepSeekProvider(configYaml)) {
      final apiKey = _deepSeekApiKey(env);
      if (apiKey.isNotEmpty) {
        usedIds.add('deepseek');
        providers.add(
          HermesImportedProvider(
            config: ProviderConfig(
              id: 'deepseek',
              name: 'DeepSeek',
              colorValue: _colorFor('deepseek'),
              order: 0,
              enabled: false,
              baseUrl: 'https://api.deepseek.com/v1',
              defaultModel: 'deepseek-chat',
            ),
            apiKey: apiKey,
          ),
        );
      }
    }
    return HermesImportPlan(List.unmodifiable(providers));
  }

  List<HermesImportedProvider> _parseProviders(
    String yaml,
    Map<String, String> env,
    Set<String> usedIds,
  ) {
    final records = <_ProviderRecord>[];
    var inProviders = false;
    _ProviderRecord? current;
    for (final rawLine in yaml.split(RegExp(r'\r?\n'))) {
      if (rawLine.trim().isEmpty || rawLine.trimLeft().startsWith('#')) {
        continue;
      }
      final indent = rawLine.length - rawLine.trimLeft().length;
      final line = rawLine.trim();
      if (!inProviders) {
        if (indent == 0 && line == 'providers:') inProviders = true;
        continue;
      }
      if (indent == 0) break;
      final providerMatch = RegExp(
        r'^  ([A-Za-z0-9_-]+):\s*$',
      ).firstMatch(rawLine);
      if (providerMatch != null) {
        if (current != null) records.add(current);
        current = _ProviderRecord(providerMatch.group(1)!);
        continue;
      }
      final fieldMatch = RegExp(
        r'^    ([A-Za-z0-9_]+):\s*(.*)$',
      ).firstMatch(rawLine);
      if (fieldMatch != null && current != null) {
        current.values[fieldMatch.group(1)!] = _yamlScalar(
          fieldMatch.group(2)!,
        );
      }
    }
    if (current != null) records.add(current);
    return [
      for (final record in records) ?_toImportedProvider(record, env, usedIds),
    ];
  }

  List<HermesImportedProvider> _parseCustomProviders(
    String yaml,
    Map<String, String> env,
    Set<String> usedIds,
  ) {
    final records = <_ProviderRecord>[];
    var inCustomProviders = false;
    _ProviderRecord? current;
    for (final rawLine in yaml.split(RegExp(r'\r?\n'))) {
      if (rawLine.trim().isEmpty || rawLine.trimLeft().startsWith('#')) {
        continue;
      }
      final indent = rawLine.length - rawLine.trimLeft().length;
      final line = rawLine.trim();
      if (!inCustomProviders) {
        if (indent == 0 && line == 'custom_providers:') {
          inCustomProviders = true;
        }
        continue;
      }
      if (indent == 0) break;
      final providerMatch = RegExp(r'^  -\s+name:\s*(.*)$').firstMatch(rawLine);
      if (providerMatch != null) {
        if (current != null) records.add(current);
        current = _ProviderRecord(providerMatch.group(1)!.trim())
          ..values['name'] = _yamlScalar(providerMatch.group(1)!);
        continue;
      }
      final fieldMatch = RegExp(
        r'^    ([A-Za-z0-9_]+):\s*(.*)$',
      ).firstMatch(rawLine);
      if (fieldMatch != null && current != null) {
        current.values[fieldMatch.group(1)!] = _yamlScalar(
          fieldMatch.group(2)!,
        );
      }
    }
    if (current != null) records.add(current);
    return [
      for (final record in records) ?_toImportedProvider(record, env, usedIds),
    ];
  }

  HermesImportedProvider? _toImportedProvider(
    _ProviderRecord record,
    Map<String, String> env,
    Set<String> usedIds,
  ) {
    final baseUrl = record.values['base_url']?.trim() ?? '';
    if (baseUrl.isEmpty) return null;
    final originalId = _safeId(record.id);
    var id = originalId;
    var suffix = 2;
    while (!usedIds.add(id)) {
      id = '$originalId-import-${suffix++}';
    }
    final name = record.values['name']?.trim().isNotEmpty == true
        ? record.values['name']!.trim()
        : record.id;
    return HermesImportedProvider(
      config: ProviderConfig(
        id: id,
        name: name,
        colorValue: _colorFor(id),
        order: 0,
        enabled: false,
        baseUrl: baseUrl,
        defaultModel:
            record.values['default_model']?.trim() ??
            record.values['model']?.trim() ??
            '',
      ),
      apiKey: _resolveApiKey(record.values, env),
    );
  }

  Map<String, String> _parseEnv(String envFile) {
    final variables = <String, String>{};
    for (final rawLine in envFile.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(
        r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$',
      ).firstMatch(line);
      if (match != null) {
        variables[match.group(1)!] = _yamlScalar(match.group(2)!);
      }
    }
    return variables;
  }

  String _resolveApiKey(Map<String, String> values, Map<String, String> env) {
    final inline = values['api_key']?.trim() ?? '';
    if (inline.isNotEmpty) return inline;
    final keyEnv = values['key_env']?.trim() ?? '';
    return keyEnv.isEmpty ? '' : env[keyEnv]?.trim() ?? '';
  }

  String _deepSeekApiKey(Map<String, String> env) {
    for (final entry in env.entries) {
      if (RegExp(
        '^DEEPSEEK(?:_[A-Z0-9]+)*_API_KEY'
        r'$',
        caseSensitive: false,
      ).hasMatch(entry.key)) {
        final value = entry.value.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  bool _hasExplicitDeepSeekProvider(String yaml) {
    for (final rawLine in yaml.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (RegExp(
            '^deepseek\\s*:'
            r'$',
            caseSensitive: false,
          ).hasMatch(line) ||
          RegExp(
            '^-?\\s*name\\s*:\\s*deepseek\\s*'
            r'$',
            caseSensitive: false,
          ).hasMatch(line)) {
        return true;
      }
    }
    return false;
  }

  String _yamlScalar(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        trimmed.startsWith('"') &&
        trimmed.endsWith('"')) {
      final unquoted = trimmed.substring(1, trimmed.length - 1);
      return _decodeEscapedScalar(unquoted);
    }
    if (trimmed.length >= 2 &&
        trimmed.startsWith("'") &&
        trimmed.endsWith("'")) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return _decodeEscapedScalar(trimmed);
  }

  String _decodeEscapedScalar(String value) {
    if (!value.contains(r'\')) {
      return value;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char != r'\') {
        buffer.write(char);
        continue;
      }
      if (i + 1 >= value.length) {
        buffer.write(r'\');
        continue;
      }
      final escape = value[++i];
      switch (escape) {
        case 'b':
          buffer.write('\b');
        case 'f':
          buffer.write('\f');
        case 'n':
          buffer.write('\n');
        case 'r':
          buffer.write('\r');
        case 't':
          buffer.write('\t');
        case '"':
          buffer.write('"');
        case r'\':
          buffer.write(r'\');
        case '/':
          buffer.write('/');
        case 'u':
          if (i + 4 >= value.length) {
            return value;
          }
          final hex = value.substring(i + 1, i + 5);
          final codePoint = int.tryParse(hex, radix: 16);
          if (codePoint == null) {
            return value;
          }
          buffer.write(String.fromCharCode(codePoint));
          i += 4;
        default:
          buffer.write(r'\');
          buffer.write(escape);
      }
    }
    return buffer.toString();
  }

  String _safeId(String source) {
    final result = source.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]+'),
      '-',
    );
    return result.replaceAll(RegExp(r'^-+|-+$'), '').isEmpty
        ? 'hermes-provider'
        : result;
  }

  int _colorFor(String id) {
    const colors = [0xff39c5bb, 0xff365edc, 0xffe77f9e, 0xffab78e8, 0xffe0a437];
    return colors[id.codeUnits.fold<int>(0, (sum, value) => sum + value) %
        colors.length];
  }
}

class HermesImportPlan {
  const HermesImportPlan(this.providers);
  final List<HermesImportedProvider> providers;
}

class HermesImportedProvider {
  const HermesImportedProvider({required this.config, this.apiKey = ''});

  final ProviderConfig config;

  /// Stored by [StorageService] in secure storage, never in [config].
  final String apiKey;
  final bool baseMetadataOnly = true;
}

class HermesImportException implements Exception {
  const HermesImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _ProviderRecord {
  _ProviderRecord(this.id);
  final String id;
  final Map<String, String> values = {};
}
