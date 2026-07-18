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
