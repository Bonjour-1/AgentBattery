import 'dart:io';

import 'package:flutter/services.dart';

import '../models/custom_theme.dart';
import '../services/theme_background_store.dart';

const sceneryGiftThemeId = '1158ab5d-f579-499e-b32a-ba020fd8c895';
const _sceneryAssetPath = 'assets/themes/scenery.png';

final sceneryGiftTheme = CustomTheme(
  id: sceneryGiftThemeId,
  name: '风景',
  layout: ThemeLayout.stage,
  palette: const ThemePalette(
    primary: 4288662015,
    secondary: 1793907675,
    stage: 2797005823,
    content: 4289506476,
    pageBackground: 4289506476,
    card: 16777215,
    dialogBackground: 16777215,
    cardAlt: 4290034687,
    text: 4278190080,
    mutedText: 4287330201,
    onStage: 4288662015,
    outline: 4291015932,
    success: 4279286166,
    error: 4294197086,
    statusIdle: 4287323382,
    shadow: 4281740929,
  ),
  cardRadius: 27,
  controlRadius: 33,
  contentRadius: 31,
  shadowOpacity: 0,
  stageOverlayOpacity: 0,
  stageGradientSecondary: 2690318335,
  stageGradientDirection: GradientDirection.topBottom,
  contentGradientSecondary: 8289918,
  contentGradientDirection: GradientDirection.diagonal,
  cardGradientDirection: GradientDirection.diagonal,
  backgroundImageFit: BackgroundImageFit.cover,
  backgroundImageAlignment: BackgroundImageAlignment.center,
  backgroundImageOpacity: 1,
  dashboardLayoutMode: DashboardLayoutMode.standard,
  dashboardDensity: DashboardDensity.comfortable,
);

typedef SceneryAssetWriter = Future<File> Function();

class SceneryGiftThemeInstaller {
  SceneryGiftThemeInstaller({SceneryAssetWriter? writeAsset})
    : _writeAsset = writeAsset ?? _writeAssetToTemporaryFile;

  final SceneryAssetWriter _writeAsset;

  Future<CustomTheme> install(ThemeBackgroundService backgrounds) async {
    final source = await _writeAsset();
    try {
      final fileName = await backgrounds.importFile(
        themeId: sceneryGiftThemeId,
        source: source,
      );
      return sceneryGiftTheme.copyWith(backgroundImageFileName: fileName);
    } finally {
      try {
        if (await source.exists()) await source.delete();
      } on FileSystemException {
        // The managed copy is already complete; temp cleanup is best-effort.
      }
    }
  }

  static Future<File> _writeAssetToTemporaryFile() async {
    final bytes = await rootBundle.load(_sceneryAssetPath);
    final directory = await Directory.systemTemp.createTemp(
      'agentbattery-scenery-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}scenery.png');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file;
  }
}
