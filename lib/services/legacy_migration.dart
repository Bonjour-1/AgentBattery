import 'dart:convert';

import '../models/app_snapshot.dart';
import '../models/provider_usage.dart';

class LegacyMigration {
  static AppSnapshot? parseJson(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      final providers = <String, ProviderUsage>{};
      for (final id in const ['deepseek', 'kimi']) {
        final raw = decoded[id];
        if (raw is Map) {
          providers[id] = ProviderUsage.fromJson(
            Map<String, Object?>.from(raw),
          );
        }
      }
      final ui = decoded['ui'];
      final themeName = ui is Map
          ? ui['theme']?.toString().toLowerCase()
          : null;
      final theme = switch (themeName) {
        'miku' => AppTheme.miku,
        'cute' => AppTheme.cute,
        'mita' => AppTheme.mita,
        _ => AppTheme.glass,
      };
      return AppSnapshot(providers: providers, theme: theme);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class LegacyKeyParser {
  static final _line = RegExp(r'^(.+?)[\(（]([\w]+)[\)）]\s*$');
  static Map<String, String> parse(String content) {
    final keys = <String, String>{};
    for (final source in const ['deepseek', 'kimi', 'pucoding']) {
      for (final line in const LineSplitter().convert(content)) {
        final match = _line.firstMatch(line.trim());
        if (match != null && match.group(2)!.toLowerCase() == source) {
          keys[source] = match.group(1)!.trim();
        }
      }
    }
    return keys;
  }
}
