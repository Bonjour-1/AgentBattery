import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_snapshot.dart';
import '../models/provider_config.dart';

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
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
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
  ProviderKeyManager(this._store);

  static const _prefix = 'agentbattery/provider/';
  final SecureKeyStore _store;

  static String keyFor(String providerId) => '$_prefix$providerId';
  static String balanceTokenKeyFor(String providerId) =>
      '${_prefix}balance-token/$providerId';

  Future<KeyHydrationResult> hydrateAndMigrate(
    AppSnapshot snapshot, {
    Map<String, String> importedKeys = const {},
  }) async {
    final pending = <String, String>{};
    final configs = <ProviderConfig>[];
    for (final config in snapshot.providerConfigs) {
      final jsonLegacyKey = config.apiKey;
      final legacyKey = jsonLegacyKey.isNotEmpty
          ? jsonLegacyKey
          : importedKeys[config.id] ?? '';
      if (legacyKey.isNotEmpty) {
        final storedBalanceToken = await _readBalanceToken(config.id);
        if (await _writeAndVerify(config.id, legacyKey)) {
          configs.add(
            config.copyWith(
              apiKey: legacyKey,
              balanceToken: storedBalanceToken,
            ),
          );
        } else if (jsonLegacyKey.isNotEmpty) {
          pending[config.id] = jsonLegacyKey;
          configs.add(
            config.copyWith(
              apiKey: jsonLegacyKey,
              balanceToken: storedBalanceToken,
            ),
          );
        } else {
          configs.add(config.copyWith(balanceToken: storedBalanceToken));
        }
      } else {
        String? storedKey;
        String? storedBalanceToken;
        try {
          storedKey = await _store.read(keyFor(config.id));
          storedBalanceToken = await _store.read(balanceTokenKeyFor(config.id));
        } catch (_) {
          // Treat an unavailable key store as a missing key without losing config.
        }
        configs.add(
          config.copyWith(
            apiKey: storedKey ?? '',
            balanceToken: storedBalanceToken ?? '',
          ),
        );
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
    if (!await _writeAndVerify(id, submittedKey)) {
      throw StateError('Unable to securely save provider API key.');
    }
    return submittedKey;
  }

  Future<String?> _readBalanceToken(String providerId) async {
    try {
      return await _store.read(balanceTokenKeyFor(providerId));
    } catch (_) {
      return null;
    }
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
    if (!await _writeAndVerifyAt(balanceTokenKeyFor(id), token)) {
      throw StateError('Unable to securely save provider balance token.');
    }
    return token;
  }

  Future<void> deleteForProvider(String providerId) async {
    await _store.delete(keyFor(providerId));
    await _store.delete(balanceTokenKeyFor(providerId));
  }

  Future<bool> _writeAndVerify(String providerId, String value) =>
      _writeAndVerifyAt(keyFor(providerId), value);

  Future<bool> _writeAndVerifyAt(String key, String value) async {
    try {
      await _store.write(key, value);
      return await _store.read(key) == value;
    } catch (_) {
      return false;
    }
  }
}
