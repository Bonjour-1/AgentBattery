import 'custom_theme.dart';
import 'provider_config.dart';
import 'provider_usage.dart';

export 'custom_theme.dart' show AppTheme, ThemeReference;

class AppSnapshot {
  const AppSnapshot({
    this.providers = const {},
    this.providerConfigs = const [],
    AppTheme theme = AppTheme.miku,
    ThemeReference? themeReference,
    this.customThemes = const [],
    this.autoRefreshEnabled = false,
    this.autoRefreshIntervalSeconds = 60,
    this.windowShowHotkey = 'ctrl+alt+b',
  }) : _legacyTheme = theme,
       _storedThemeReference = themeReference;

  final Map<String, ProviderUsage> providers;
  final List<ProviderConfig> providerConfigs;
  final AppTheme _legacyTheme;
  final ThemeReference? _storedThemeReference;
  ThemeReference get themeReference =>
      _storedThemeReference ?? ThemeReference.builtin(_legacyTheme);
  final List<CustomTheme> customThemes;
  final bool autoRefreshEnabled;
  final int autoRefreshIntervalSeconds;
  final String windowShowHotkey;

  /// Compatibility bridge for existing runtime code until Task 2 resolves
  /// custom themes into tokens. A custom reference intentionally falls back.
  AppTheme get theme => themeReference.builtinTheme ?? AppTheme.miku;

  AppSnapshot copyWith({
    Map<String, ProviderUsage>? providers,
    List<ProviderConfig>? providerConfigs,
    AppTheme? theme,
    ThemeReference? themeReference,
    List<CustomTheme>? customThemes,
    bool? autoRefreshEnabled,
    int? autoRefreshIntervalSeconds,
    String? windowShowHotkey,
  }) => AppSnapshot(
    providers: providers ?? this.providers,
    providerConfigs: providerConfigs ?? this.providerConfigs,
    theme: theme ?? this.theme,
    themeReference:
        themeReference ??
        (theme == null ? this.themeReference : ThemeReference.builtin(theme)),
    customThemes: customThemes ?? this.customThemes,
    autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
    autoRefreshIntervalSeconds:
        autoRefreshIntervalSeconds ?? this.autoRefreshIntervalSeconds,
    windowShowHotkey: windowShowHotkey ?? this.windowShowHotkey,
  );

  Map<String, Object?> toJson() => {
    'version': 3,
    'providers': providers.map((key, value) => MapEntry(key, value.toJson())),
    'provider_configs': providerConfigs.map((item) => item.toJson()).toList(),
    'theme_reference': themeReference.toJson(),
    'custom_themes': customThemes.map((item) => item.toJson()).toList(),
    if (themeReference.isBuiltin) 'theme': themeReference.builtinTheme!.name,
    'auto_refresh_enabled': autoRefreshEnabled,
    'auto_refresh_interval_seconds': autoRefreshIntervalSeconds,
    'window_show_hotkey': windowShowHotkey,
  };

  factory AppSnapshot.fromJson(Map<String, Object?> json) {
    final rawUsage = json['providers'];
    final providers = <String, ProviderUsage>{};
    if (rawUsage is Map) {
      for (final entry in rawUsage.entries) {
        if (entry.key is String && entry.value is Map) {
          providers[entry.key as String] = ProviderUsage.fromJson(
            Map<String, Object?>.from(entry.value as Map),
          );
        }
      }
    }
    final rawConfigs = json['provider_configs'];
    final parsedConfigs = rawConfigs is List
        ? rawConfigs
              .whereType<Map>()
              .map(
                (item) =>
                    ProviderConfig.fromJson(Map<String, Object?>.from(item)),
              )
              .where((item) => item.id.isNotEmpty)
              .toList()
        : builtinProviderTemplates;
    final configs = List<ProviderConfig>.from(parsedConfigs)
      ..sort((a, b) => a.order.compareTo(b.order));
    final rawSeconds = json['auto_refresh_interval_seconds'];
    final rawMinutes = json['auto_refresh_interval_minutes'];
    final interval = rawSeconds is int && rawSeconds >= 1 && rawSeconds <= 86400
        ? rawSeconds
        // The minutes field only exists in the erroneous minutes release, so
        // preserve its numeric value as seconds instead of multiplying it.
        : rawMinutes is int && rawMinutes >= 1 && rawMinutes <= 86400
        ? rawMinutes
        : 60;
    final customThemes = _parseCustomThemes(json['custom_themes']);
    final reference = _parseThemeReference(json);
    final activeReference =
        reference.customThemeId != null &&
            !customThemes.any((item) => item.id == reference.customThemeId)
        ? const ThemeReference.builtin(AppTheme.miku)
        : reference;
    return AppSnapshot(
      providers: providers,
      providerConfigs: configs,
      themeReference: activeReference,
      customThemes: customThemes,
      autoRefreshEnabled: json['auto_refresh_enabled'] == true,
      autoRefreshIntervalSeconds: interval,
      windowShowHotkey: json['window_show_hotkey'] is String
          ? json['window_show_hotkey'] as String
          : 'ctrl+alt+b',
    );
  }

  static List<CustomTheme> _parseCustomThemes(Object? raw) {
    if (raw is! List) return const [];
    final ids = <String>{};
    final themes = <CustomTheme>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final theme = CustomTheme.fromJson(Map<String, Object?>.from(item));
        if (ids.add(theme.id)) themes.add(theme);
      } on ArgumentError {
        // A bad persisted custom theme must not prevent application startup.
      }
    }
    return List.unmodifiable(themes);
  }

  static ThemeReference _parseThemeReference(Map<String, Object?> json) {
    if (json.containsKey('theme_reference')) {
      return ThemeReference.fromJson(json['theme_reference']);
    }
    return ThemeReference.builtin(_parseLegacyTheme(json['theme']));
  }

  static AppTheme _parseLegacyTheme(Object? value) => switch (value) {
    'glass' || 'other' => AppTheme.glass,
    'cute' => AppTheme.cute,
    'mita' => AppTheme.mita,
    'nailong' => AppTheme.nailong,
    _ => AppTheme.miku,
  };
}
