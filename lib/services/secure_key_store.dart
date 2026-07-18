import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_snapshot.dart';
import '../models/provider_config.dart';
import 'app_storage_scope.dart';
import 'web_billing_migrations.dart';

abstract interface class SecureKeyStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class KeyHydrationResult {
  const KeyHydrationResult({
    required this.snapshot,
    required this.pendingLegacyKeys,
  });
  final AppSnapshot snapshot;
  final Map<String, String> pendingLegacyKeys;
}

class ProviderKeyManager {
  ProviderKeyManager(this._store, {String? prefix})
    : _prefix = prefix ?? AppStorageScope.securePrefix;

  final String _prefix;
  final SecureKeyStore _store;

  static String keyFor(
    String providerId, {
    String prefix = 'agentbattery/provider/',
  }) => '$prefix$providerId';
  static String balanceTokenKeyFor(
    String providerId, {
    String prefix = 'agentbattery/provider/',
  }) => '${prefix}balance-token/$providerId';
  static String billCookieKeyFor(
    String providerId, {
    String prefix = 'agentbattery/provider/',
  }) => '${prefix}bill-cookie/$providerId';
  static String walletCookieKeyFor(
    String providerId, {
    String prefix = 'agentbattery/provider/',
  }) => '${prefix}wallet-cookie/$providerId';
  static String walletSubjectIdKeyFor(
    String providerId, {
    String prefix = 'agentbattery/provider/',
  }) => '${prefix}wallet-subject-id/$providerId';

  /// Namespace for generic web-billing variables. Values never enter config JSON.
  static String webBillingVariableKeyFor(
    String providerId,
    String variableId, {
    String prefix = 'agentbattery/provider/',
  }) => '${prefix}web-billing-variable/$providerId/$variableId';

  String _keyFor(String id) => keyFor(id, prefix: _prefix);
  String _balanceTokenKeyFor(String id) =>
      balanceTokenKeyFor(id, prefix: _prefix);
  String _billCookieKeyFor(String id) => billCookieKeyFor(id, prefix: _prefix);
  String _walletCookieKeyFor(String id) =>
      walletCookieKeyFor(id, prefix: _prefix);
  String _walletSubjectIdKeyFor(String id) =>
      walletSubjectIdKeyFor(id, prefix: _prefix);
  String _webBillingVariableKeyFor(String providerId, String variableId) =>
      webBillingVariableKeyFor(providerId, variableId, prefix: _prefix);

  Future<KeyHydrationResult> hydrateAndMigrate(
    AppSnapshot snapshot, {
    Map<String, String> importedKeys = const {},
  }) async {
    final pending = <String, String>{};
    final configs = <ProviderConfig>[];
    for (final config in snapshot.providerConfigs) {
      final jsonLegacyKey = config.apiKey;
      final importedKey = importedKeys[config.id] ?? '';
      final legacyKey = importedKey.isNotEmpty ? importedKey : jsonLegacyKey;
      final storedBalanceToken = await _read(_balanceTokenKeyFor(config.id));
      final storedBillCookie = await _read(_billCookieKeyFor(config.id));
      final storedWalletCookie = await _read(_walletCookieKeyFor(config.id));
      final storedWalletSubjectId = await _read(
        _walletSubjectIdKeyFor(config.id),
      );
      await _migrateRecognizedLegacyWebBillingSecrets(
        config,
        apiKey: await _read(_keyFor(config.id)),
        balanceToken: storedBalanceToken,
        walletCookie: storedWalletCookie,
        walletSubjectId: storedWalletSubjectId,
      );
      ProviderConfig withSecrets(ProviderConfig value) => value.copyWith(
        balanceToken: storedBalanceToken ?? '',
        billCookie: storedBillCookie ?? '',
        walletCookie: storedWalletCookie ?? '',
        walletSubjectId: storedWalletSubjectId ?? '',
      );
      if (legacyKey.isNotEmpty) {
        if (await _writeAndVerify(_keyFor(config.id), legacyKey)) {
          configs.add(withSecrets(config.copyWith(apiKey: legacyKey)));
        } else if (jsonLegacyKey.isNotEmpty) {
          pending[config.id] = jsonLegacyKey;
          configs.add(withSecrets(config.copyWith(apiKey: jsonLegacyKey)));
        } else {
          configs.add(withSecrets(config));
        }
      } else {
        final storedKey = await _read(_keyFor(config.id));
        configs.add(withSecrets(config.copyWith(apiKey: storedKey ?? '')));
      }
    }
    return KeyHydrationResult(
      snapshot: snapshot.copyWith(providerConfigs: configs),
      pendingLegacyKeys: pending,
    );
  }

  Future<String> saveForProvider({
    required String id,
    required String submittedKey,
    required String existingKey,
  }) async {
    if (submittedKey.isEmpty) return existingKey;
    if (!await _writeAndVerify(_keyFor(id), submittedKey)) {
      throw StateError('Unable to securely save provider API key.');
    }
    return submittedKey;
  }

  Future<String> saveBalanceToken({
    required String id,
    required String submittedToken,
    required String existingToken,
  }) async {
    if (submittedToken.isEmpty) return existingToken;
    final token = submittedToken.replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );
    if (!await _writeAndVerify(_balanceTokenKeyFor(id), token)) {
      throw StateError('Unable to securely save provider balance token.');
    }
    return token;
  }

  Future<String> saveBillCookie({
    required String id,
    required String submittedCookie,
    required String existingCookie,
  }) async {
    if (submittedCookie.isEmpty) return existingCookie;
    if (!await _writeAndVerify(_billCookieKeyFor(id), submittedCookie)) {
      throw StateError('Unable to securely save provider billing cookie.');
    }
    return submittedCookie;
  }

  Future<String> saveWalletCookie({
    required String id,
    required String submittedCookie,
    required String existingCookie,
  }) => _saveSecret(_walletCookieKeyFor(id), submittedCookie, existingCookie);

  Future<String> saveWalletSubjectId({
    required String id,
    required String submittedSubjectId,
    required String existingSubjectId,
  }) => _saveSecret(
    _walletSubjectIdKeyFor(id),
    submittedSubjectId,
    existingSubjectId,
  );

  Future<void> saveWebBillingVariable({
    required String providerId,
    required String variableId,
    required String submittedValue,
  }) async {
    if (submittedValue.isEmpty) return;
    if (!await _writeAndVerify(
      webBillingVariableKeyFor(providerId, variableId, prefix: _prefix),
      submittedValue,
    )) {
      throw StateError('Unable to securely save web billing variable.');
    }
  }

  /// Reads a generic web-billing secret by the variable identifier used as its
  /// secure-storage key. Callers must not log the returned value.
  Future<String?> readWebBillingVariable({
    required String providerId,
    required String variableId,
  }) async {
    final value = await _read(
      webBillingVariableKeyFor(providerId, variableId, prefix: _prefix),
    );
    if (value?.isNotEmpty == true || variableId != 'API_KEY') return value;
    return _read(_keyFor(providerId));
  }

  /// Returns only a length-preserving display mask, never a stored secret.
  Future<String?> readProviderApiKeyMask(String providerId) async =>
      _mask(await _read(_keyFor(providerId)));

  /// Returns masks only for declared variables. This deliberately accepts the
  /// definitions, rather than arbitrary caller-supplied storage-key names.
  Future<Map<String, String>> readWebBillingVariableMasks({
    required String providerId,
    required Iterable<String> variableIds,
  }) async {
    final masks = <String, String>{};
    for (final variableId in variableIds.toSet()) {
      final value = await readWebBillingVariable(
        providerId: providerId,
        variableId: variableId,
      );
      final mask = _mask(value);
      if (mask != null) masks[variableId] = mask;
    }
    return masks;
  }

  Future<void> _migrateRecognizedLegacyWebBillingSecrets(
    ProviderConfig config, {
    required String? apiKey,
    required String? balanceToken,
    required String? walletCookie,
    required String? walletSubjectId,
  }) async {
    if (!isRecognizedLegacyWebBillingConfig(config)) return;
    switch (config.id) {
      case 'deepseek':
        await _copyWebBillingVariableIfMissing(
          config.id,
          'DEEPSEEK_API_KEY',
          apiKey,
        );
        await _copyWebBillingVariableIfMissing(
          config.id,
          'DEEPSEEK_WEB_BEARER',
          balanceToken,
        );
      case 'siliconflow':
        await _copyWebBillingVariableIfMissing(
          config.id,
          'COOKIE',
          walletCookie,
        );
        await _copyWebBillingVariableIfMissing(
          config.id,
          'SUBJECT_ID',
          walletSubjectId,
        );
      case 'codeapi':
      case 'codeapi-claude':
        await _copyWebBillingVariableIfMissing(
          config.id,
          'CODEAPI_WEB_BEARER',
          balanceToken,
        );
    }
  }

  Future<void> _copyWebBillingVariableIfMissing(
    String providerId,
    String variableId,
    String? legacyValue,
  ) async {
    if (legacyValue == null || legacyValue.isEmpty) return;
    final key = _webBillingVariableKeyFor(providerId, variableId);
    if (await _read(key) != null) return;
    await _writeAndVerify(key, legacyValue);
  }

  Future<String> _saveSecret(
    String key,
    String submitted,
    String existing,
  ) async {
    if (submitted.isEmpty) return existing;
    if (!await _writeAndVerify(key, submitted)) {
      throw StateError('Unable to securely save provider credential.');
    }
    return submitted;
  }

  Future<void> deleteForProvider(
    String providerId, {
    Iterable<String> declaredWebBillingVariableIds = const [],
  }) async {
    await _store.delete(_keyFor(providerId));
    await _store.delete(_balanceTokenKeyFor(providerId));
    await _store.delete(_billCookieKeyFor(providerId));
    await _store.delete(_walletCookieKeyFor(providerId));
    await _store.delete(_walletSubjectIdKeyFor(providerId));
    for (final variableId in declaredWebBillingVariableIds.toSet()) {
      if (variableId.isEmpty) continue;
      await _store.delete(_webBillingVariableKeyFor(providerId, variableId));
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _store.read(key);
    } catch (_) {
      return null;
    }
  }

  static String? _mask(String? value) {
    if (value == null || value.isEmpty) return null;
    return '•' * value.length.clamp(0, 256);
  }

  Future<bool> _writeAndVerify(String key, String value) async {
    try {
      await _store.write(key, value);
      return await _store.read(key) == value;
    } catch (_) {
      return false;
    }
  }
}
