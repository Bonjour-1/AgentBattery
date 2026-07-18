import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/app_snapshot.dart';
import '../models/custom_theme.dart';
import '../models/provider_config.dart';
import '../models/provider_usage.dart';
import '../models/provider_view_state.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../services/theme_background_store.dart';
import '../services/theme_package_service.dart';
import '../ui/theme/app_theme_tokens.dart';
import '../ui/theme/resolved_theme.dart';
import '../ui/window_layout_policy.dart';

class BatteryController extends ChangeNotifier {
  BatteryController({
    required StorageService storage,
    required ApiClient api,
    ThemeBackgroundService? backgrounds,
    ThemePackageService? themePackages,
  }) : this._withBackgroundService(
         storage: storage,
         api: api,
         backgrounds: backgrounds ?? ThemeBackgroundStore(),
         themePackages: themePackages ?? ThemePackageService(),
       );

  BatteryController._withBackgroundService({
    required this._storage,
    required this._api,
    required this._backgrounds,
    required this._themePackages,
  });

  final StorageService _storage;
  final ApiClient _api;
  final ThemeBackgroundService _backgrounds;
  final ThemePackageService _themePackages;
  AppSnapshot _snapshot = const AppSnapshot();
  bool loading = true;
  bool refreshing = false;
  DateTime? lastRefresh;
  Timer? _autoRefreshTimer;
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
  double get totalDaily =>
      visibleProviders.fold(0, (sum, item) => sum + item.dailyUsage);
  double get totalMonthly =>
      visibleProviders.fold(0, (sum, item) => sum + item.monthlyUsage);

  Future<void> initialize({bool refreshOnStart = true}) async {
    _snapshot = await _storage.load();
    _snapshot = _snapshot.copyWith(
      providerConfigs: [
        for (final config in _snapshot.providerConfigs)
          if (config.id == 'pucoding')
            config.copyWith(
              advancedEnabled: true,
              balanceUrl:
                  config.balanceUrl.isEmpty ||
                      config.balanceUrl == 'https://pucoding.com/api/v1/user/info'
                  ? 'https://pucoding.com/api/v1/user/account'
                  : config.balanceUrl,
              balanceJsonPath: config.balanceJsonPath.isEmpty
                  ? 'data.balance'
                  : config.balanceJsonPath,
              dailyUsageJsonPath: '',
              monthlyUsageJsonPath: '',
            )
          else if (config.id == 'codeapi' &&
              !config.advancedEnabled &&
              (config.balanceUrl.trim().isNotEmpty ||
                  config.balanceJsonPath.trim().isNotEmpty))
            config.copyWith(
              advancedEnabled: true,
              balanceUrl: 'https://codeapi.icu/api/portal/usage',
              balanceMethod: BalanceRequestMethod.post,
              balanceBody: '{"key":"\${API_KEY}","page":1,"pageSize":1}',
              balanceJsonPath: 'balance_usd',
              dailyUsageJsonPath: 'today_cost_usd',
            )
          else
            config,
      ],
    );
    await _persist();
    _rebuildViews();
    loading = false;
    notifyListeners();
    _configureAutoRefresh();
    if (refreshOnStart) unawaited(refresh());
  }

  void _rebuildViews() {
    for (final config in configs) {
      final usage = _snapshot.providers[config.id];
      providers[config.id] = ProviderViewState(
        id: config.id,
        name: config.name,
        balance: usage?.lastBalance,
        dailyUsage: usage?.dailyUsage ?? 0,
        monthlyUsage: usage?.monthlyUsage ?? 0,
        status: config.apiKey.isEmpty
            ? ConnectionStatus.noKey
            : ConnectionStatus.cached,
        message: config.apiKey.isEmpty ? '未配置 Key' : '已载入缓存',
      );
    }
    providers.removeWhere((id, _) => !configs.any((config) => config.id == id));
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    for (final config in enabledConfigs) {
      providers[config.id] = providers[config.id]!.copyWith(
        status: ConnectionStatus.refreshing,
        message: '正在更新',
      );
    }
    notifyListeners();
    await Future.wait(enabledConfigs.map(_refreshProvider));
    refreshing = false;
    lastRefresh = DateTime.now();
    await _persist();
    notifyListeners();
  }

  Future<void> _refreshProvider(ProviderConfig config) async {
    if (config.apiKey.isEmpty) {
      providers[config.id] = providers[config.id]!.copyWith(
        status: ConnectionStatus.noKey,
        message: '未配置 Key',
      );
      return;
    }
    if (!config.advancedEnabled ||
        config.balanceUrl.trim().isEmpty ||
        config.balanceJsonPath.trim().isEmpty) {
      try {
        await _api.validate(config);
        providers[config.id] = providers[config.id]!.copyWith(
          status: ConnectionStatus.unavailable,
          message: '已连接 · 余额不可查询',
        );
      } catch (_) {
        providers[config.id] = providers[config.id]!.copyWith(
          status: ConnectionStatus.error,
          message: '连接失败，显示缓存',
        );
      }
      return;
    }
    try {
      final response = await _api.fetchBalance(config);
      var usage = (_snapshot.providers[config.id] ?? const ProviderUsage())
          .recordBalance(response.balance, DateTime.now());
      if (response.dailyUsage != null || response.monthlyUsage != null) {
        usage = ProviderUsage(
          date: usage.date,
          month: usage.month,
          lastBalance: response.balance,
          dailyUsage: response.dailyUsage ?? usage.dailyUsage,
          monthlyUsage: response.monthlyUsage ?? usage.monthlyUsage,
        );
      }
      _snapshot = _snapshot.copyWith(
        providers: {..._snapshot.providers, config.id: usage},
      );
      providers[config.id] = providers[config.id]!.copyWith(
        balance: response.balance,
        dailyUsage: usage.dailyUsage,
        monthlyUsage: usage.monthlyUsage,
        status: ConnectionStatus.connected,
        message: '已连接',
      );
    } catch (_) {
      providers[config.id] = providers[config.id]!.copyWith(
        status: ConnectionStatus.error,
        message: '更新失败，显示缓存',
      );
    }
    notifyListeners();
  }

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

  Future<void> saveProvider(ProviderConfig config) async {
    final current = configs.where((item) => item.id != config.id).toList();
    final id = config.id.isEmpty
        ? 'provider_${DateTime.now().microsecondsSinceEpoch}'
        : config.id;
    final existing = <ProviderConfig>[
      for (final item in configs)
        if (item.id == id) item,
    ];
    final apiKey = await _storage.saveProviderKey(
      id: id,
      submittedKey: config.apiKey,
      existingKey: existing.isEmpty ? '' : existing.first.apiKey,
    );
    final balanceToken = await _storage.saveProviderBalanceToken(
      id: id,
      submittedToken: config.balanceToken,
      existingToken: existing.isEmpty ? '' : existing.first.balanceToken,
    );
    current.add(
      config.copyWith(
        id: id,
        apiKey: apiKey,
        balanceToken: balanceToken,
        order: config.id.isEmpty ? current.length : config.order,
      ),
    );
    _snapshot = _snapshot.copyWith(providerConfigs: _ordered(current));
    _rebuildViews();
    await _persist();
    notifyListeners();
  }

  Future<void> deleteProvider(String id) async {
    await _storage.deleteProviderKey(id);
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
        content: tokens.scaffold.toARGB32(),
        card: tokens.surface.toARGB32(),
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
