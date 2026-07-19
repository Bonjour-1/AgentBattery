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
    pageBackground: 0xffe9fffd,
    card: 0xfff3fffe,
    dialogBackground: 0xfff3fffe,
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

  test(
    'round trips split surface colors and exports their exact keys',
    () async {
      final splitTheme = _theme.copyWith(
        palette: _theme.palette.copyWith(
          pageBackground: 0xff313233,
          dialogBackground: 0xff343536,
        ),
      );
      final package = File(
        '${root.path}${Platform.pathSeparator}split.agentbattery-theme',
      );

      await service.exportTheme(splitTheme, destination: package);
      final imported = await service.readPackage(package);
      final archive = ZipDecoder().decodeBytes(await package.readAsBytes());
      final manifestFile = archive.files.singleWhere(
        (entry) => entry.name == 'manifest.json',
      );
      final manifest = Map<String, Object?>.from(
        jsonDecode(utf8.decode(List<int>.from(manifestFile.content))) as Map,
      );
      final themeJson = Map<String, Object?>.from(manifest['theme']! as Map);
      final paletteJson = Map<String, Object?>.from(
        themeJson['palette']! as Map,
      );

      expect(imported.theme, splitTheme);
      expect(paletteJson['page_background'], 0xff313233);
      expect(paletteJson['dialog_background'], 0xff343536);
    },
  );

  test('accepts legacy packages without split surface keys', () async {
    final legacyManifest = _manifest();
    final legacyTheme = Map<String, Object?>.from(
      legacyManifest['theme']! as Map,
    );
    final legacyPalette =
        Map<String, Object?>.from(legacyTheme['palette']! as Map)
          ..remove('page_background')
          ..remove('dialog_background');
    legacyTheme['palette'] = legacyPalette;
    legacyManifest['theme'] = legacyTheme;
    final package = await _zip(root, {
      'manifest.json': utf8.encode(jsonEncode(legacyManifest)),
    });

    final imported = await service.readPackage(package);

    expect(
      imported.theme.palette.pageBackground,
      imported.theme.palette.content,
    );
    expect(
      imported.theme.palette.dialogBackground,
      imported.theme.palette.card,
    );
  });

  test('rejects packages with only one split surface key', () async {
    for (final missingKey in ['page_background', 'dialog_background']) {
      final partialManifest = _manifest();
      final partialTheme = Map<String, Object?>.from(
        partialManifest['theme']! as Map,
      );
      final partialPalette = Map<String, Object?>.from(
        partialTheme['palette']! as Map,
      )..remove(missingKey);
      partialTheme['palette'] = partialPalette;
      partialManifest['theme'] = partialTheme;
      final package = await _zip(root, {
        'manifest.json': utf8.encode(jsonEncode(partialManifest)),
      });

      await expectLater(
        service.readPackage(package),
        throwsA(isA<ThemePackageException>()),
      );
    }
  });

  test('rejects unknown palette keys', () async {
    final invalidManifest = _manifest();
    final invalidTheme = Map<String, Object?>.from(
      invalidManifest['theme']! as Map,
    );
    invalidTheme['palette'] = {
      ...Map<String, Object?>.from(invalidTheme['palette']! as Map),
      'unexpected_surface': 0xff000000,
    };
    invalidManifest['theme'] = invalidTheme;
    final package = await _zip(root, {
      'manifest.json': utf8.encode(jsonEncode(invalidManifest)),
    });

    await expectLater(
      service.readPackage(package),
      throwsA(isA<ThemePackageException>()),
    );
  });

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
