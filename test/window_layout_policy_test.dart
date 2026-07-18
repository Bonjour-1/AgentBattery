import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/ui/window_layout_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MIKU uses the horizontal stage window policy', () {
    final policy = WindowLayoutPolicy.forTheme(AppTheme.miku);

    expect(policy.size, const Size(1320, 760));
    expect(policy.minimumSize, const Size(1080, 680));
  });

  test('Mita uses the horizontal character-stage window policy', () {
    final policy = WindowLayoutPolicy.forTheme(AppTheme.mita);

    expect(policy.size, const Size(1320, 760));
    expect(policy.minimumSize, const Size(1080, 680));
  });

  test('Nailong uses the horizontal character-stage window policy', () {
    final policy = WindowLayoutPolicy.forTheme(AppTheme.nailong);

    expect(policy.size, const Size(1320, 760));
    expect(policy.minimumSize, const Size(1080, 680));
  });

  test('glass and cute use the compact window policy', () {
    for (final theme in [AppTheme.glass, AppTheme.cute]) {
      final policy = WindowLayoutPolicy.forTheme(theme);

      expect(policy.size, const Size(680, 800));
      expect(policy.minimumSize, const Size(620, 720));
    }
  });
}
