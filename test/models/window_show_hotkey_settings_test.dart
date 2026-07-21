import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists the default global window-show hotkey', () {
    final stored = const AppSnapshot().toJson();

    expect(stored['window_show_hotkey'], 'ctrl+alt+b');
  });
}
