import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_snapshot.dart';
import '../models/provider_config.dart';
import 'app_storage_scope.dart';
import 'hermes_provider_importer.dart';
import 'secure_key_store.dart';
import 'web_billing_migrations.dart';

class StorageService {
  StorageService({SecureKeyStore? keyStore, String? stateKey})
    : _keys = ProviderKeyManager(keyStore ?? FlutterSecureKeyStore()),
      _stateKey = stateKey ?? AppStorageScope.stateKey;

  final String _stateKey;

  final ProviderKeyManager _keys;
  Map<String, String> _pendingLegacyKeys = {};

  Future<AppSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_stateKey);
    if (stored != null) {
      try {
        final raw = Map<String, Object?>.from(jsonDecode(stored) as Map);
        final snapshot = _migrateLegacyBilling(raw);
        if (raw['provider_configs'] is List) {
          final hydrated = await _keys.hydrateAndMigrate(snapshot);
          _pendingLegacyKeys = hydrated.pendingLegacyKeys;
          await save(hydrated.snapshot);
          return hydrated.snapshot;
        }
        final migrated = snapshot.copyWith(
          providerConfigs: await _builtinConfigs(),
        );
        final hydrated = await _keys.hydrateAndMigrate(migrated);
        _pendingLegacyKeys = hydrated.pendingLegacyKeys;
        await save(hydrated.snapshot);
        return hydrated.snapshot;
      } catch (_) {
        // A damaged cache should not prevent startup.
      }
    }
    const snapshot = AppSnapshot();
    final configured = snapshot.copyWith(
      providerConfigs: await _builtinConfigs(),
    );
    final hydrated = await _keys.hydrateAndMigrate(configured);
    _pendingLegacyKeys = hydrated.pendingLegacyKeys;
    await save(hydrated.snapshot);
    return hydrated.snapshot;
  }

  Future<List<ProviderConfig>> _builtinConfigs() async =>
      builtinProviderTemplates;

  /// Reads retired billing JSON before [ProviderConfig.fromJson] intentionally
  /// drops it, and attaches its generic replacement to the clean model.
  AppSnapshot _migrateLegacyBilling(Map<String, Object?> raw) {
    final parsed = AppSnapshot.fromJson(raw);
    final rawConfigs = raw['provider_configs'];
    if (rawConfigs is! List) return parsed;
    final legacyById = <String, LegacyBillingSnapshot>{};
    for (final item in rawConfigs.whereType<Map>()) {
      final json = Map<String, Object?>.from(item);
      final id = json['id']?.toString() ?? '';
      if (id.isNotEmpty) legacyById[id] = LegacyBillingSnapshot.fromJson(json);
    }
    final configs = parsed.providerConfigs.map((config) {
      return migrateLegacyProviderToWebBillingConfig(
        config,
        legacyById[config.id],
      );
    }).toList();
    return parsed.copyWith(providerConfigs: configs);
  }

  Future<String> saveProviderKey({
    required String id,
    required String submittedKey,
    required String existingKey,
  }) async {
    final resolved = await _keys.saveForProvider(
      id: id,
      submittedKey: submittedKey,
      existingKey: existingKey,
    );
    if (submittedKey.isNotEmpty) _pendingLegacyKeys.remove(id);
    return resolved;
  }

  Future<String> saveProviderBalanceToken({
    required String id,
    required String submittedToken,
    required String existingToken,
  }) => _keys.saveBalanceToken(
    id: id,
    submittedToken: submittedToken,
    existingToken: existingToken,
  );

  Future<String> saveProviderBillCookie({
    required String id,
    required String submittedCookie,
    required String existingCookie,
  }) => _keys.saveBillCookie(
    id: id,
    submittedCookie: submittedCookie,
    existingCookie: existingCookie,
  );

  Future<String> saveProviderWalletCookie({
    required String id,
    required String submittedCookie,
    required String existingCookie,
  }) => _keys.saveWalletCookie(
    id: id,
    submittedCookie: submittedCookie,
    existingCookie: existingCookie,
  );

  Future<String> saveProviderWalletSubjectId({
    required String id,
    required String submittedSubjectId,
    required String existingSubjectId,
  }) => _keys.saveWalletSubjectId(
    id: id,
    submittedSubjectId: submittedSubjectId,
    existingSubjectId: existingSubjectId,
  );

  Future<void> saveProviderWebBillingVariables(
    String providerId,
    Map<String, String> candidates,
  ) async {
    for (final entry in candidates.entries) {
      await _keys.saveWebBillingVariable(
        providerId: providerId,
        variableId: entry.key,
        submittedValue: entry.value,
      );
    }
  }

  Future<String?> readProviderApiKeyMask(String providerId) =>
      _keys.readProviderApiKeyMask(providerId);

  Future<Map<String, String>> readProviderWebBillingVariableMasks(
    String providerId,
    Iterable<String> declaredVariableIds,
  ) => _keys.readWebBillingVariableMasks(
    providerId: providerId,
    variableIds: declaredVariableIds,
  );

  Future<void> deleteProviderKey(String id) async {
    await deleteProviderSecrets(id, const []);
  }

  /// Deletes the provider API key, retired known secrets, and only the generic
  /// web-billing variables declared by the provider configuration.
  Future<void> deleteProviderSecrets(
    String providerId,
    Iterable<String> declaredWebBillingVariableIds,
  ) async {
    await _keys.deleteForProvider(
      providerId,
      declaredWebBillingVariableIds: declaredWebBillingVariableIds,
    );
    _pendingLegacyKeys.remove(providerId);
  }

  /// Imports Hermes connection metadata and model API keys only.
  ///
  /// Imported API keys replace existing provider API keys only when non-empty,
  /// and are written exclusively through the secure key store. Billing
  /// configuration, billing secrets, runtime state, enablement, and ordering
  /// are never changed by this path.
  Future<AppSnapshot> importHermesProviders(
    AppSnapshot snapshot,
    List<HermesImportedProvider> imported,
  ) async {
    final byId = {
      for (final config in snapshot.providerConfigs) config.id: config,
    };
    for (final item in imported) {
      final existing = byId[item.config.id];
      final importedKey = item.apiKey.trim();
      final merged = existing == null
          ? item.config.copyWith(order: byId.length)
          : mergeHermesBasicMetadata(existing, item.config);
      if (importedKey.isEmpty) {
        byId[item.config.id] = merged;
        continue;
      }
      final savedKey = await saveProviderKey(
        id: item.config.id,
        submittedKey: importedKey,
        existingKey: existing?.apiKey ?? '',
      );
      byId[item.config.id] = merged.copyWith(apiKey: savedKey);
    }
    final result = snapshot.copyWith(providerConfigs: byId.values.toList());
    await save(result);
    return result;
  }

  /// Retains every non-metadata field from [existing].
  ProviderConfig mergeHermesBasicMetadata(
    ProviderConfig existing,
    ProviderConfig imported,
  ) => existing.copyWith(
    name: imported.name,
    baseUrl: imported.baseUrl,
    defaultModel: imported.defaultModel,
  );

  Future<void> save(AppSnapshot snapshot) async {
    final state = snapshot.toJson();
    final configs = state['provider_configs']! as List<Object?>;
    for (final config in configs.whereType<Map<String, Object?>>()) {
      final legacyKey = _pendingLegacyKeys[config['id']];
      if (legacyKey != null) config['api_key'] = legacyKey;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state));
  }
}
