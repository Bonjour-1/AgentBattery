import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/app_snapshot.dart';
import '../models/custom_theme.dart';
import '../models/provider_config.dart';
import '../models/provider_usage.dart';
import '../models/provider_view_state.dart';
import '../models/web_billing_config.dart';
import '../services/api_client.dart';
import '../services/hermes_provider_importer.dart';
import '../services/storage_service.dart';
import '../services/theme_background_store.dart';
import '../services/theme_package_service.dart';
import '../themes/scenery_gift_theme.dart';
import '../ui/theme/app_theme_tokens.dart';
import '../ui/theme/resolved_theme.dart';
import '../ui/window_layout_policy.dart';

class BatteryController extends ChangeNotifier {
  BatteryController({
    required StorageService storage,
    required ApiClient api,
    ThemeBackgroundService? backgrounds,
    ThemePackageService? themePackages,
    SceneryGiftThemeInstaller? sceneryGiftThemeInstaller,
  }) : this._withBackgroundService(
         storage: storage,
         api: api,
         backgrounds: backgrounds ?? ThemeBackgroundStore(),
         themePackages: themePackages ?? ThemePackageService(),
         sceneryGiftThemeInstaller:
             sceneryGiftThemeInstaller ?? SceneryGiftThemeInstaller(),
       );

  BatteryController._withBackgroundService({
    required this._storage,
    required this._api,
    required this._backgrounds,
    required this._themePackages,
    required this._sceneryGiftThemeInstaller,
  });

  final StorageService _storage;
  final ApiClient _api;
  final ThemeBackgroundService _backgrounds;
  final ThemePackageService _themePackages;
  final SceneryGiftThemeInstaller _sceneryGiftThemeInstaller;
  AppSnapshot _snapshot = const AppSnapshot();
  bool loading = true;
  bool refreshing = false;
  DateTime? lastRefresh;
  Timer? _autoRefreshTimer;
  Future<void>? _refreshFuture;
  AppTheme get theme => _snapshot.theme;
  List<CustomTheme> get customThemes =>
      List.unmodifiable(_snapshot.customThemes);
  ThemeReference get themeReference => _snapshot.themeReference;
  ResolvedTheme get resolvedTheme {
    final reference = themeReference;
    if (reference case ThemeReference(builtinTheme: final theme?)) {
      return ResolvedTheme.builtin(theme);
    }
    final customTheme = _customThemeFor(reference.customThemeId);
    return customTheme == null
        ? ResolvedTheme.builtin(AppTheme.miku)
        : ResolvedTheme.custom(customTheme);
  }

  bool get autoRefreshEnabled => _snapshot.autoRefreshEnabled;
  int get autoRefreshIntervalSeconds => _snapshot.autoRefreshIntervalSeconds;
  String get windowShowHotkey => _snapshot.windowShowHotkey;
  List<ProviderConfig> get configs => List.unmodifiable(
    List<ProviderConfig>.from(_snapshot.providerConfigs)
      ..sort((a, b) => a.order.compareTo(b.order)),
  );
  final Map<String, ProviderViewState> providers = {};
  Iterable<ProviderConfig> get enabledConfigs =>
      configs.where((item) => item.enabled);
  Iterable<ProviderViewState> get visibleProviders => enabledConfigs
      .map((config) => providers[config.id]!)
      .whereType<ProviderViewState>();
  double get totalBalance => visibleProviders
      .where((item) => item.balance != null)
      .fold(0, (sum, item) => sum + item.balance!);
  double get totalDaily => visibleProviders.fold(
    0,
    (sum, item) => sum + (item.dailyDisplayUsage ?? 0),
  );
  double get totalMonthly => visibleProviders.fold(
    0,
    (sum, item) => sum + (item.monthlyDisplayUsage ?? 0),
  );

  Future<void> initialize({
    bool refreshOnStart = true,
    bool installSceneryGiftTheme = false,
  }) async {
    _snapshot = await _storage.load();
    if (installSceneryGiftTheme) await _installSceneryGiftTheme();
    _rebuildViews();
    loading = false;
    notifyListeners();
    _configureAutoRefresh();
    if (refreshOnStart) unawaited(refresh());
  }

  Future<void> _installSceneryGiftTheme() async {
    if (_snapshot.customThemes.any((theme) => theme.id == sceneryGiftThemeId)) {
      return;
    }
    try {
      final installed = await _sceneryGiftThemeInstaller.install(_backgrounds);
      _snapshot = _snapshot.copyWith(
        customThemes: [..._snapshot.customThemes, installed],
      );
      await _persist();
    } catch (_) {
      // A gift resource must never prevent the dashboard from opening.
    }
  }

  void _rebuildViews() {
    for (final config in configs) {
      final usage = _snapshot.providers[config.id];
      providers[config.id] = ProviderViewState(
        id: config.id,
        name: config.name,
        balance: usage?.lastBalance,
        dailyUsage: usage?.dailyUsage ?? 0,
        dailyDisplayUsage: _initialDisplay(
          usage?.dailyUsage ?? 0,
          _policyFor(config, WebBillingMetricKind.daily),
        ),
        monthlyUsage: usage?.monthlyUsage ?? 0,
        monthlyDisplayUsage: _initialDisplay(
          usage?.monthlyUsage ?? 0,
          _policyFor(config, WebBillingMetricKind.monthly),
        ),
        status: config.apiKey.isEmpty
            ? ConnectionStatus.noKey
            : ConnectionStatus.cached,
        message: config.apiKey.isEmpty ? '未配置 Key' : '已载入缓存',
      );
    }
    providers.removeWhere((id, _) => !configs.any((config) => config.id == id));
  }

  Future<void> refresh() => _refreshFuture ??= _performRefresh();

  Future<void> _performRefresh() async {
    refreshing = true;
    try {
      for (final config in enabledConfigs) {
        providers[config.id] = providers[config.id]!.copyWith(
          status: ConnectionStatus.refreshing,
          message: '正在更新',
        );
      }
      notifyListeners();
      await Future.wait(enabledConfigs.map(_refreshProvider));
      lastRefresh = DateTime.now();
      await _persist();
      notifyListeners();
    } finally {
      refreshing = false;
      _refreshFuture = null;
    }
  }

  Future<void> _refreshProvider(ProviderConfig config) async {
    try {
      final response = await _api.fetchMetrics(config);
      final cachedUsage =
          _snapshot.providers[config.id] ?? const ProviderUsage();
      final dailySucceeded =
          _hasMetric(config, WebBillingMetricKind.daily) &&
          response.dailySucceeded;
      final monthlySucceeded =
          _hasMetric(config, WebBillingMetricKind.monthly) &&
          response.monthlySucceeded;
      final dailyEstimate =
          !dailySucceeded &&
          _policyFor(config, WebBillingMetricKind.daily) ==
              MetricFailureDisplay.estimateFallback &&
          cachedUsage.lastBalance != null;
      final monthlyEstimate =
          !monthlySucceeded &&
          _policyFor(config, WebBillingMetricKind.monthly) ==
              MetricFailureDisplay.estimateFallback &&
          cachedUsage.lastBalance != null;
      final usage = cachedUsage.recordMetrics(
        response.balance,
        DateTime.now(),
        dailyUsage: dailySucceeded ? response.dailyUsage : null,
        monthlyUsage: monthlySucceeded ? response.monthlyUsage : null,
        estimateDailyFromBalance: dailyEstimate,
        estimateMonthlyFromBalance: monthlyEstimate,
      );
      _snapshot = _snapshot.copyWith(
        providers: {..._snapshot.providers, config.id: usage},
      );
      providers[config.id] = providers[config.id]!.copyWith(
        balance: response.balance,
        dailyUsage: usage.dailyUsage,
        dailyDisplayUsage: _displayAfterMetric(
          succeeded: dailySucceeded,
          estimated: dailyEstimate,
          showCached:
              _policyFor(config, WebBillingMetricKind.daily) ==
              MetricFailureDisplay.showCached,
          usage: usage.dailyUsage,
        ),
        clearDailyDisplayUsage:
            !dailySucceeded &&
            !dailyEstimate &&
            _policyFor(config, WebBillingMetricKind.daily) !=
                MetricFailureDisplay.showCached,
        monthlyUsage: usage.monthlyUsage,
        monthlyDisplayUsage: _displayAfterMetric(
          succeeded: monthlySucceeded,
          estimated: monthlyEstimate,
          showCached:
              _policyFor(config, WebBillingMetricKind.monthly) ==
              MetricFailureDisplay.showCached,
          usage: usage.monthlyUsage,
        ),
        clearMonthlyDisplayUsage:
            !monthlySucceeded &&
            !monthlyEstimate &&
            _policyFor(config, WebBillingMetricKind.monthly) !=
                MetricFailureDisplay.showCached,
        status: ConnectionStatus.connected,
        message: _metricMessage(config, response),
      );
    } catch (error) {
      providers[config.id] = providers[config.id]!.copyWith(
        clearBalance:
            _policyFor(config, WebBillingMetricKind.balance) ==
            MetricFailureDisplay.hide,
        clearDailyDisplayUsage:
            _policyFor(config, WebBillingMetricKind.daily) ==
            MetricFailureDisplay.hide,
        clearMonthlyDisplayUsage:
            _policyFor(config, WebBillingMetricKind.monthly) ==
            MetricFailureDisplay.hide,
        status: ConnectionStatus.error,
        message: '网页账单更新失败：${_safeError(error)}，显示缓存',
      );
    }
    notifyListeners();
  }

  String _metricMessage(ProviderConfig config, BalanceResponse response) {
    final failures = [
      response.dailyFailure,
      response.monthlyFailure,
    ].whereType<String>().toSet().toList();
    if (failures.isNotEmpty) {
      return '网页账单更新失败：${failures.join(' / ')}，显示缓存';
    }
    final dailySucceeded =
        _hasMetric(config, WebBillingMetricKind.daily) &&
        response.dailySucceeded;
    final monthlySucceeded =
        _hasMetric(config, WebBillingMetricKind.monthly) &&
        response.monthlySucceeded;
    if (dailySucceeded && monthlySucceeded) {
      return '已连接 · 服务端今日/本月账单';
    }
    if (monthlySucceeded) return '已连接 · 服务端本月账单';
    if (dailySucceeded) return '已连接 · 服务端今日账单';
    return '已连接';
  }

  bool _hasMetric(ProviderConfig config, WebBillingMetricKind kind) =>
      config.webBillingConfig?.metricRules.any((rule) => rule.kind == kind) ??
      false;

  MetricFailureDisplay _policyFor(
    ProviderConfig config,
    WebBillingMetricKind kind,
  ) {
    final billing = config.webBillingConfig;
    final policy = billing?.displayPolicy;
    if (billing == null) return MetricFailureDisplay.showCached;
    return switch (kind) {
      WebBillingMetricKind.balance =>
        policy?.balance ?? MetricFailureDisplay.hide,
      WebBillingMetricKind.daily => policy?.daily ?? MetricFailureDisplay.hide,
      WebBillingMetricKind.monthly =>
        policy?.monthly ?? MetricFailureDisplay.hide,
    };
  }

  double? _initialDisplay(double usage, MetricFailureDisplay policy) =>
      policy == MetricFailureDisplay.hide ? null : usage;

  double? _displayAfterMetric({
    required bool succeeded,
    required bool estimated,
    required bool showCached,
    required double usage,
  }) => succeeded || estimated || showCached ? usage : null;

  String _safeError(Object error) =>
      error is ApiException ? error.message : '账单请求失败';

  Future<void> setManualUsage({
    required String providerId,
    required UsagePeriod period,
    required double amount,
  }) async {
    final usage = _snapshot.providers[providerId];
    if (usage == null) return;
    final updatedUsage = switch (period) {
      UsagePeriod.daily => usage.withDailyUsage(amount),
      UsagePeriod.monthly => usage.withMonthlyUsage(amount),
    };
    _snapshot = _snapshot.copyWith(
      providers: {..._snapshot.providers, providerId: updatedUsage},
    );
    _rebuildViews();
    await _persist();
    notifyListeners();
  }

  Future<String?> validate(ProviderConfig config) async {
    if (config.baseUrl.trim().isEmpty || config.apiKey.trim().isEmpty) {
      return '请填写 Base URL 和 API Key';
    }
    try {
      await _api.validate(config);
      return null;
    } catch (error) {
      return error is ApiException ? error.message : '验证失败';
    }
  }

  Future<String?> providerApiKeyMask(String providerId) =>
      _storage.readProviderApiKeyMask(providerId);

  Future<Map<String, String>> providerWebBillingVariableMasks(
    String providerId,
    Iterable<String> declaredVariableIds,
  ) => _storage.readProviderWebBillingVariableMasks(
    providerId,
    declaredVariableIds,
  );

  Future<void> saveProvider(
    ProviderConfig config, {
    Map<String, String> webBillingSecretCandidates = const {},
  }) async {
    final id = config.id.isEmpty
        ? 'provider_${DateTime.now().microsecondsSinceEpoch}'
        : config.id;
    final existingIndex = configs.indexWhere((item) => item.id == id);
    final hasExistingProvider = existingIndex >= 0;
    final existing = hasExistingProvider ? configs[existingIndex] : null;
    final apiKey = await _storage.saveProviderKey(
      id: id,
      submittedKey: config.apiKey,
      existingKey: existing?.apiKey ?? '',
    );
    await _storage.saveProviderWebBillingVariables(
      id,
      webBillingSecretCandidates,
    );
    final saved = config.copyWith(
      id: id,
      apiKey: apiKey,
      order: hasExistingProvider ? existing!.order : configs.length,
    );
    final updated = configs.toList();
    if (!hasExistingProvider) {
      updated.add(saved);
    } else {
      updated[existingIndex] = saved;
    }
    _snapshot = _snapshot.copyWith(providerConfigs: _ordered(updated));
    _rebuildViews();
    await _persist();
    notifyListeners();
  }

  Future<HermesImportPlan> readHermesImportPlan() =>
      const HermesProviderImporter().readDefaultFiles();

  Future<void> importHermesProviders(HermesImportPlan plan) async {
    _snapshot = await _storage.importHermesProviders(_snapshot, plan.providers);
    _rebuildViews();
    notifyListeners();
  }

  Future<void> deleteProvider(String id) async {
    final declaredVariables = configs
        .where((item) => item.id == id)
        .expand(
          (item) =>
              item.webBillingConfig?.secretVariableDefinitions ??
              const <SecretVariableDefinition>[],
        )
        .map((definition) => definition.name);
    await _storage.deleteProviderSecrets(id, declaredVariables);
    _snapshot = _snapshot.copyWith(
      providerConfigs: _ordered(
        configs.where((item) => item.id != id).toList(),
      ),
      providers: {..._snapshot.providers}..remove(id),
    );
    _rebuildViews();
    await _persist();
    notifyListeners();
  }

  Future<void> toggleProvider(String id, bool enabled) async =>
      _replace(id, (item) => item.copyWith(enabled: enabled));
  Future<void> moveProvider(String id, int delta) async {
    final ordered = configs.toList();
    final index = ordered.indexWhere((item) => item.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= ordered.length) return;
    final item = ordered.removeAt(index);
    ordered.insert(target, item);
    _snapshot = _snapshot.copyWith(providerConfigs: _ordered(ordered));
    await _persist();
    notifyListeners();
  }

  Future<void> _replace(
    String id,
    ProviderConfig Function(ProviderConfig) update,
  ) async {
    _snapshot = _snapshot.copyWith(
      providerConfigs: _ordered(
        configs.map((item) => item.id == id ? update(item) : item).toList(),
      ),
    );
    _rebuildViews();
    await _persist();
    notifyListeners();
  }

  List<ProviderConfig> _ordered(List<ProviderConfig> source) => [
    for (final entry in source.indexed) entry.$2.copyWith(order: entry.$1),
  ];
  Future<void> _persist() => _storage.save(_snapshot);
  Future<void> selectTheme(AppTheme value) async {
    await applyThemeReference(ThemeReference.builtin(value));
  }

  CustomTheme copyBuiltinTheme(AppTheme theme) {
    final tokens = AppThemeTokens.forTheme(theme);
    return CustomTheme(
      id: _randomUuid(),
      name: '${tokens.name} 副本',
      layout: switch (ResolvedTheme.builtin(theme).layout) {
        final layout when layout == WindowLayoutPolicy.compact =>
          ThemeLayout.dashboard,
        _ => ThemeLayout.stage,
      },
      palette: ThemePalette(
        primary: tokens.primary.toARGB32(),
        secondary: tokens.secondary.toARGB32(),
        stage: tokens.stageGradient.colors.first.toARGB32(),
        content: tokens.contentGradient.colors.first.toARGB32(),
        pageBackground: tokens.pageBackground.toARGB32(),
        card: tokens.cardGradient.colors.first.toARGB32(),
        dialogBackground: tokens.dialogBackground.toARGB32(),
        cardAlt: tokens.surfaceAlt.toARGB32(),
        text: tokens.text.toARGB32(),
        mutedText: tokens.mutedText.toARGB32(),
        onStage: tokens.onStage.toARGB32(),
        outline: tokens.outline.toARGB32(),
        success: tokens.success.toARGB32(),
        error: tokens.error.toARGB32(),
        statusIdle: tokens.statusIdle.toARGB32(),
        shadow: tokens.shadow.toARGB32(),
      ),
      cardRadius: tokens.cardRadius,
      controlRadius: tokens.controlRadius,
      contentRadius: tokens.contentRadius,
      shadowOpacity: .4,
      stageOverlayOpacity: .3,
      stageGradientSecondary: _secondGradientColor(tokens.stageGradient),
      stageGradientDirection: _gradientDirection(tokens.stageGradient),
      contentGradientSecondary: _secondGradientColor(tokens.contentGradient),
      contentGradientDirection: _gradientDirection(tokens.contentGradient),
      cardGradientSecondary: _secondGradientColor(tokens.cardGradient),
      cardGradientDirection: _gradientDirection(tokens.cardGradient),
    );
  }

  int? _secondGradientColor(LinearGradient gradient) =>
      gradient.colors.length > 1 && gradient.colors.first != gradient.colors[1]
      ? gradient.colors[1].toARGB32()
      : null;

  GradientDirection _gradientDirection(LinearGradient gradient) {
    if (gradient.begin == Alignment.centerLeft &&
        gradient.end == Alignment.centerRight) {
      return GradientDirection.leftRight;
    }
    if (gradient.begin == Alignment.topLeft &&
        gradient.end == Alignment.bottomRight) {
      return GradientDirection.diagonal;
    }
    return GradientDirection.topBottom;
  }

  Future<void> saveCustomTheme(CustomTheme theme) async {
    final updated = [
      for (final item in customThemes)
        if (item.id == theme.id) theme else item,
      if (!_snapshot.customThemes.any((item) => item.id == theme.id)) theme,
    ];
    await _updateThemes(updated);
  }

  Future<void> applyThemeReference(ThemeReference reference) async {
    final appliedReference =
        reference.isBuiltin || _customThemeFor(reference.customThemeId) != null
        ? reference
        : const ThemeReference.builtin(AppTheme.miku);
    _snapshot = _snapshot.copyWith(themeReference: appliedReference);
    await _persist();
    notifyListeners();
  }

  Future<void> renameCustomTheme(String id, String name) async {
    final existing = _customThemeFor(id);
    if (existing == null) return;
    await _updateThemes([
      for (final item in customThemes)
        if (item.id == id) item.copyWith(name: name) else item,
    ]);
  }

  Future<void> deleteCustomTheme(String id) async {
    final existing = _customThemeFor(id);
    if (existing == null) return;
    final background = existing.backgroundImageFileName;
    if (background != null) await _backgrounds.delete(background);
    final reference = themeReference.customThemeId == id
        ? const ThemeReference.builtin(AppTheme.miku)
        : themeReference;
    _snapshot = _snapshot.copyWith(
      customThemes: customThemes.where((item) => item.id != id).toList(),
      themeReference: reference,
    );
    await _persist();
    notifyListeners();
  }

  Future<File> exportCustomTheme(String id, File destination) async {
    final theme = _customThemeFor(id);
    if (theme == null) {
      throw ArgumentError.value(id, 'id', 'must identify a saved custom theme');
    }
    final backgroundName = theme.backgroundImageFileName;
    final background = backgroundName == null
        ? null
        : await _backgrounds.resolve(backgroundName);
    if (backgroundName != null && background == null) {
      throw StateError('The custom theme background image is unavailable.');
    }
    return _themePackages.exportTheme(
      theme,
      destination: destination,
      background: background,
    );
  }

  Future<CustomTheme> importCustomTheme(
    File packageFile, {
    bool apply = false,
  }) async {
    final package = await _themePackages.readPackage(packageFile);
    final previousSnapshot = _snapshot;
    String? importedBackground;
    try {
      final imported = package.theme.copyWith(
        id: _randomUuid(),
        name: _importedThemeName(package.theme.name),
        clearBackgroundImage: true,
      );
      final background = package.background;
      if (background != null) {
        importedBackground = await _backgrounds.importFile(
          themeId: imported.id,
          source: background,
        );
      }
      final saved = importedBackground == null
          ? imported
          : imported.copyWith(backgroundImageFileName: importedBackground);
      _snapshot = _snapshot.copyWith(
        customThemes: [...customThemes, saved],
        themeReference: apply
            ? ThemeReference.custom(saved.id)
            : themeReference,
      );
      await _persist();
      notifyListeners();
      return saved;
    } on Object {
      _snapshot = previousSnapshot;
      if (importedBackground != null) {
        try {
          await _backgrounds.delete(importedBackground);
        } on Object {
          // Preserve the import failure; orphan cleanup is best effort.
        }
      }
      rethrow;
    } finally {
      await package.dispose();
    }
  }

  static String _importedThemeName(String name) {
    const suffix = ' 导入';
    final maxBaseLength = 32 - suffix.length;
    return '${name.substring(0, min(name.length, maxBaseLength))}$suffix';
  }

  Future<void> importCustomThemeBackground(String themeId, File source) async {
    final existing = _customThemeFor(themeId);
    if (existing == null) return;
    final newFileName = await _backgrounds.importFile(
      themeId: themeId,
      source: source,
    );
    final updatedTheme = existing.copyWith(
      backgroundImageFileName: newFileName,
    );
    await _updateThemes([
      for (final item in customThemes)
        if (item.id == themeId) updatedTheme else item,
    ]);
    final oldFileName = existing.backgroundImageFileName;
    if (oldFileName != null) await _backgrounds.delete(oldFileName);
  }

  /// Resolves a saved custom theme's managed background for local presentation.
  /// The caller receives only the managed [File], never the storage path model.
  Future<File?> resolveCustomThemeBackground(String themeId) async {
    final fileName = _customThemeFor(themeId)?.backgroundImageFileName;
    if (fileName == null) return null;
    try {
      return await _backgrounds.resolve(fileName);
    } on Object {
      return null;
    }
  }

  /// Resolves only the active custom theme's managed background. Missing or
  /// unreadable files are intentionally rendered as no background at runtime.
  Future<File?> resolveActiveThemeBackground() async {
    final customTheme = _customThemeFor(themeReference.customThemeId);
    final fileName = customTheme?.backgroundImageFileName;
    if (fileName == null) return null;
    try {
      return await _backgrounds.resolve(fileName);
    } on Object {
      return null;
    }
  }

  Future<void> removeCustomThemeBackground(String themeId) async {
    final existing = _customThemeFor(themeId);
    final oldFileName = existing?.backgroundImageFileName;
    if (existing == null || oldFileName == null) return;
    await _updateThemes([
      for (final item in customThemes)
        if (item.id == themeId)
          item.copyWith(clearBackgroundImage: true)
        else
          item,
    ]);
    await _backgrounds.delete(oldFileName);
  }

  Future<void> _updateThemes(List<CustomTheme> themes) async {
    _snapshot = _snapshot.copyWith(customThemes: themes);
    await _persist();
    notifyListeners();
  }

  CustomTheme? _customThemeFor(String? id) {
    if (id == null) return null;
    for (final item in _snapshot.customThemes) {
      if (item.id == id) return item;
    }
    return null;
  }

  static String _randomUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<void> setAutoRefresh({
    required bool enabled,
    required int intervalSeconds,
  }) async {
    final normalizedInterval = intervalSeconds.clamp(1, 86400);
    _snapshot = _snapshot.copyWith(
      autoRefreshEnabled: enabled,
      autoRefreshIntervalSeconds: normalizedInterval,
    );
    _configureAutoRefresh();
    await _persist();
    notifyListeners();
  }

  Future<void> setWindowShowHotkey(String shortcut) async {
    _snapshot = _snapshot.copyWith(windowShowHotkey: shortcut);
    await _persist();
    notifyListeners();
  }

  void _configureAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    if (!autoRefreshEnabled) return;
    _autoRefreshTimer = Timer.periodic(
      Duration(seconds: autoRefreshIntervalSeconds),
      (_) => unawaited(refresh()),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _api.close();
    super.dispose();
  }
}
