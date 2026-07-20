import 'package:flutter/material.dart';

import '../models/custom_theme.dart';

@immutable
class WindowLayoutPolicy {
  const WindowLayoutPolicy({required this.size, required this.minimumSize});

  final Size size;
  final Size minimumSize;

  static const compact = WindowLayoutPolicy(
    size: Size(680, 800),
    minimumSize: Size(620, 720),
  );
  static const mikuStage = WindowLayoutPolicy(
    size: Size(1320, 760),
    minimumSize: Size(1080, 680),
  );

  static const mitaStage = mikuStage;
  static const nailongStage = mikuStage;

  bool isEquivalentTo(WindowLayoutPolicy other) =>
      size == other.size && minimumSize == other.minimumSize;

  static bool shouldTransition({
    required WindowLayoutPolicy? previous,
    required WindowLayoutPolicy target,
  }) => previous == null || !previous.isEquivalentTo(target);

  static Size transitionSize({
    required Size currentSize,
    required WindowLayoutPolicy target,
  }) {
    final height = currentSize.height < target.minimumSize.height
        ? target.minimumSize.height
        : currentSize.height;
    final ratio = target.size.width / target.size.height;
    final width = (height * ratio) < target.minimumSize.width
        ? target.minimumSize.width
        : height * ratio;
    return Size(width, height);
  }

  static Size? requiredSize({
    required Size currentSize,
    required Size minimumSize,
  }) {
    final required = Size(
      currentSize.width < minimumSize.width
          ? minimumSize.width
          : currentSize.width,
      currentSize.height < minimumSize.height
          ? minimumSize.height
          : currentSize.height,
    );
    return required == currentSize ? null : required;
  }

  static WindowLayoutPolicy forTheme(AppTheme theme) => switch (theme) {
    AppTheme.miku => mikuStage,
    AppTheme.mita => mitaStage,
    AppTheme.nailong => nailongStage,
    AppTheme.glass || AppTheme.cute => compact,
  };

  static WindowLayoutPolicy forCustomLayout(ThemeLayout layout) =>
      switch (layout) {
        ThemeLayout.dashboard => compact,
        ThemeLayout.stage => mikuStage,
      };
}
