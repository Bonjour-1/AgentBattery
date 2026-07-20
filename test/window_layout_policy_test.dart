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

  test('recognizes layouts with the same default window policy', () {
    expect(
      WindowLayoutPolicy.mikuStage.isEquivalentTo(WindowLayoutPolicy.mitaStage),
      isTrue,
    );
    expect(
      WindowLayoutPolicy.compact.isEquivalentTo(WindowLayoutPolicy.mikuStage),
      isFalse,
    );
  });

  test('keeps a window that already meets the next theme minimum size', () {
    expect(
      WindowLayoutPolicy.requiredSize(
        currentSize: const Size(1320, 760),
        minimumSize: WindowLayoutPolicy.compact.minimumSize,
      ),
      isNull,
    );
  });

  test('transitions from the initial compact window to an active stage layout', () {
    expect(
      WindowLayoutPolicy.shouldTransition(
        previous: null,
        target: WindowLayoutPolicy.mikuStage,
      ),
      isTrue,
    );
  });


  test('enforces the target minimum height during a transition', () {
    final size = WindowLayoutPolicy.transitionSize(
      currentSize: const Size(680, 500),
      target: WindowLayoutPolicy.mikuStage,
    );

    expect(size.height, 680);
    expect(size.width, closeTo(1181.05, .01));
  });

  test('enforces the target minimum width during a transition', () {
    final size = WindowLayoutPolicy.transitionSize(
      currentSize: const Size(1000, 10),
      target: WindowLayoutPolicy.compact,
    );

    expect(size, const Size(620, 720));
  });

  test('does not transition between equivalent stage layouts', () {
    expect(
      WindowLayoutPolicy.shouldTransition(
        previous: WindowLayoutPolicy.mikuStage,
        target: WindowLayoutPolicy.mitaStage,
      ),
      isFalse,
    );
  });

  test('keeps height and uses the dashboard aspect ratio across layouts', () {
    final size = WindowLayoutPolicy.transitionSize(
      currentSize: const Size(1320, 760),
      target: WindowLayoutPolicy.compact,
    );

    expect(size.height, 760);
    expect(size.width, 646);
  });
}
