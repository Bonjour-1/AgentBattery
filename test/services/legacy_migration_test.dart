import 'dart:convert';

import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/services/legacy_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegacyMigration', () {
    test('keeps only supported provider usage and a known theme', () {
      final result = LegacyMigration.parseJson(
        jsonEncode({
          'deepseek': {
            'date': '2026-07-10',
            'month': '2026-07',
            'last_balance': 12.34,
            'daily_cumulative': 1.2,
            'monthly_cumulative': 3.4,
          },
          'kimi': {
            'date': '2026-07-09',
            'month': '2026-07',
            'last_balance': '8.5',
            'daily_cumulative': '0.5',
            'monthly_cumulative': 2,
          },
          'glm': {'cached_key': 'must-not-migrate', 'key_valid': true},
          'date': 'obsolete',
          'ui': {'theme': 'miku', 'window_x': 100},
        }),
      );

      expect(result, isNotNull);
      expect(result!.providers.keys, {'deepseek', 'kimi'});
      expect(result.providers['deepseek']!.lastBalance, 12.34);
      expect(result.providers['deepseek']!.dailyUsage, 1.2);
      expect(result.providers['kimi']!.lastBalance, 8.5);
      expect(result.theme, AppTheme.miku);
      expect(result.toJson().toString(), isNot(contains('must-not-migrate')));
    });

    test('tolerates malformed JSON and malformed provider values', () {
      expect(LegacyMigration.parseJson('{not json'), isNull);
      final result = LegacyMigration.parseJson(
        '{"deepseek":{"last_balance":[],"daily_cumulative":-2}}',
      );
      expect(result, isNotNull);
      expect(result!.providers['deepseek']!.lastBalance, isNull);
      expect(result.providers['deepseek']!.dailyUsage, 0);
    });

    test('parses legacy key convention with ASCII or Chinese parentheses', () {
      const content = '''
secret-one(DeepSeek)
secret-two（Kimi）
secret-three（PuCoding）
ignored line
''';
      final keys = LegacyKeyParser.parse(content);
      expect(keys['deepseek'], 'secret-one');
      expect(keys['kimi'], 'secret-two');
      expect(keys['pucoding'], 'secret-three');
      expect(keys.length, 3);
    });
  });
}
