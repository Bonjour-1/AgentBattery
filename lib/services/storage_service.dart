import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_snapshot.dart';
import '../models/provider_config.dart';
import 'secure_key_store.dart';

class StorageService {
  StorageService({SecureKeyStore? keyStore})
    : _keys = ProviderKeyManager(keyStore ?? FlutterSecureKeyStore());

  static const _stateKey = 'agent_battery_state_v1';
  final ProviderKeyManager _keys;

  Future<AppSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_stateKey);
    if (stored != null) {
      try {
        final raw = Map<String, Object?>.from(jsonDecode(stored) as Map);
        final snapshot = AppSnapshot.fromJson(raw);
        final resolved = raw['provider_configs'] is List
            ? snapshot
            : snapshot.copyWith(providerConfigs: builtinProviderTemplates);
        final hydrated = await _keys.hydrateAndMigrate(resolved);
        await save(hydrated.snapshot);
        return hydrated.snapshot;
      } catch (_) {
        // A damaged cache should not prevent startup.
      }
    }
    final hydrated = await _keys.hydrateAndMigrate(
      const AppSnapshot(providerConfigs: builtinProviderTemplates),
    );
    await save(hydrated.snapshot);
    return hydrated.snapshot;
  }

  Future<String> saveProviderKey({
    required String id,
    required String submittedKey,
    required String existingKey,
  }) => _keys.saveForProvider(
    id: id,
    submittedKey: submittedKey,
    existingKey: existingKey,
  );

  Future<String> saveProviderBalanceToken({
    required String id,
    required String submittedToken,
    required String existingToken,
  }) => _keys.saveBalanceToken(
    id: id,
    submittedToken: submittedToken,
    existingToken: existingToken,
  );

  Future<void> deleteProviderKey(String id) => _keys.deleteForProvider(id);

  Future<void> save(AppSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(snapshot.toJson()));
  }
}
