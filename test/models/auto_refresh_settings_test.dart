import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists automatic refresh enabled state and custom seconds interval', () {
    const snapshot = AppSnapshot(
      autoRefreshEnabled: true,
      autoRefreshIntervalSeconds: 30,
    );

    final stored = snapshot.toJson();
    final restored = AppSnapshot.fromJson(stored);

    expect(restored.autoRefreshEnabled, isTrue);
    expect(restored.autoRefreshIntervalSeconds, 30);
    expect(stored['auto_refresh_interval_seconds'], 30);
    expect(stored.containsKey('auto_refresh_interval_minutes'), isFalse);
  });

  test('migrates erroneous minutes interval as the same seconds value', () {
    final restored = AppSnapshot.fromJson({
      'auto_refresh_interval_minutes': 5,
    });

    expect(restored.autoRefreshIntervalSeconds, 5);
  });

  test('uses sixty seconds when automatic refresh interval is absent or invalid', () {
    expect(AppSnapshot.fromJson(const {}).autoRefreshIntervalSeconds, 60);
    expect(
      AppSnapshot.fromJson({
        'auto_refresh_interval_seconds': 0,
        'auto_refresh_interval_minutes': 0,
      }).autoRefreshIntervalSeconds,
      60,
    );
  });
}
