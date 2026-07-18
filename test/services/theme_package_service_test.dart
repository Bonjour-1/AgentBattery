import 'dart:convert';
import 'dart:io';

import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/services/theme_package_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

const _themeId = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';

final _theme = CustomTheme(
  id: _themeId,
  name: 'Midnight',
  layout: ThemeLayout.stage,
  palette: const ThemePalette(
    primary: 0xff15968e,
    secondary: 0xffff8fab,
    stage: 0xff0d5753,
    content: 0xffe9fffd,
    card: 0xfff3fffe,
    cardAlt: 0xffddf8f5,
    text: 0xff123f3d,
    mutedText: 0xff557a77,
    onStage: 0xffffffff,
    outline: 0xffb6e4df,
    success: 0xff13867f,
    error: 0xffc34c70,
    statusIdle: 0xff687b79,
    shadow: 0xff0d5c57,
  ),
  cardRadius: 24,
  controlRadius: 16,
  contentRadius: 34,
  shadowOpacity: .4,
  stageOverlayOpacity: .3,
);

void main() {
  late Directory root;
  late ThemePackageService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('theme_package_service_test_');
    service = ThemePackageService(temporaryDirectory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('round trips a portable theme without a background', () async {
    final package = File(
      '${root.path}${Platform.pathSeparator}theme.agentbattery-theme',
    );

    await service.exportTheme(_theme, destination: package);
    final imported = await service.readPackage(package);

    expect(imported.theme, _theme.copyWith(clearBackgroundImage: true));
    expect(imported.background, isNull);
    expect(await package.exists(), isTrue);
  });

  test(
    'round trips one background without exposing its managed filename',
    () async {
      final source = await _write(root, 'managed-name.webp', [1, 2, 3]);
      final package = File(
        '${root.path}${Platform.pathSeparator}theme.agentbattery-theme',
      );

      await service.exportTheme(
        _theme.copyWith(backgroundImageFileName: 'machine-specific.webp'),
        destination: package,
        background: source,
      );
      final imported = await service.readPackage(package);

      expect(imported.theme.backgroundImageFileName, isNull);
      expect(imported.backgroundExtension, 'webp');
      expect(await imported.background!.readAsBytes(), [1, 2, 3]);
    },
  );

  test('rejects ZIP slip entries before writing a background file', () async {
    final package = await _zip(root, {
      '../escape.txt': [1],
      'manifest.json': utf8.encode(jsonEncode(_manifest())),
    });

    await expectLater(
      service.readPackage(package),
      throwsA(isA<ThemePackageException>()),
    );
    expect(await _files(root), hasLength(1));
  });

  test(
    'rejects malformed manifests and packages over the compressed size limit',
    () async {
      final malformed = await _zip(root, {
        'manifest.json': utf8.encode('{bad'),
      });
      final oversized = File(
        '${root.path}${Platform.pathSeparator}oversized.agentbattery-theme',
      );
      await oversized.writeAsBytes(
        List<int>.filled(ThemePackageService.maxPackageSizeBytes + 1, 0),
      );

      await expectLater(
        service.readPackage(malformed),
        throwsA(isA<ThemePackageException>()),
      );
      await expectLater(
        service.readPackage(oversized),
        throwsA(isA<ThemePackageException>()),
      );
    },
  );
}

Map<String, Object?> _manifest() => {
  'schema': ThemePackageService.schema,
  'version': ThemePackageService.version,
  'theme': _theme.copyWith(clearBackgroundImage: true).toJson(),
};

Future<File> _write(Directory root, String name, List<int> bytes) async {
  final file = File('${root.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}

Future<File> _zip(Directory root, Map<String, List<int>> entries) async {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final file = File(
    '${root.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.agentbattery-theme',
  );
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
  return file;
}

Future<List<FileSystemEntity>> _files(Directory root) => root.list().toList();
