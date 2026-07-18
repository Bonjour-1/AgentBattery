import 'dart:io';

import 'package:agent_battery_flutter/services/theme_background_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _themeId = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';

void main() {
  late Directory root;
  late ThemeBackgroundStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'theme_background_store_test_',
    );
    store = ThemeBackgroundStore(appSupportDirectory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('ThemeBackgroundStore.importFile', () {
    test('copies an allowed image and returns its managed basename', () async {
      final source = await _writeFile(root, 'source.png', [1, 2, 3]);

      final fileName = await store.importFile(
        themeId: _themeId,
        source: source,
      );
      final resolved = await store.resolve(fileName);

      expect(fileName, matches(RegExp('^$_themeId-[\\w-]+\\.png\$')));
      expect(resolved, isNotNull);
      expect(await resolved!.readAsBytes(), [1, 2, 3]);
      expect(
        await Directory(
          '${root.path}${Platform.pathSeparator}theme_backgrounds',
        ).exists(),
        isTrue,
      );
    });

    test('normalizes allowed extension case', () async {
      final source = await _writeFile(root, 'source.JPEG', [7]);

      final fileName = await store.importFile(
        themeId: _themeId,
        source: source,
      );

      expect(fileName, endsWith('.jpeg'));
    });

    test(
      'rejects a non-image source without creating a managed file',
      () async {
        final source = await _writeFile(root, 'source.txt', [1]);

        await expectLater(
          store.importFile(themeId: _themeId, source: source),
          throwsA(isA<ThemeBackgroundStoreException>()),
        );
        expect(await _managedFiles(root), isEmpty);
      },
    );

    test(
      'rejects a source larger than 15 MB without creating a managed file',
      () async {
        final source = File('${root.path}${Platform.pathSeparator}source.webp');
        await source.writeAsBytes(List<int>.filled(15 * 1024 * 1024 + 1, 0));

        await expectLater(
          store.importFile(themeId: _themeId, source: source),
          throwsA(isA<ThemeBackgroundStoreException>()),
        );
        expect(await _managedFiles(root), isEmpty);
      },
    );

    test('rejects a missing source without creating a managed file', () async {
      final source = File('${root.path}${Platform.pathSeparator}missing.png');

      await expectLater(
        store.importFile(themeId: _themeId, source: source),
        throwsA(isA<ThemeBackgroundStoreException>()),
      );
      expect(await _managedFiles(root), isEmpty);
    });
  });

  group('ThemeBackgroundStore path safety', () {
    test('rejects traversal, separators, and absolute paths', () async {
      for (final value in [
        '../background.png',
        'nested/background.png',
        r'nested\background.png',
        '${Platform.pathSeparator}absolute.png',
        r'C:\absolute.png',
      ]) {
        await expectLater(store.resolve(value), throwsArgumentError);
        await expectLater(store.delete(value), throwsArgumentError);
      }
    });

    test(
      'resolves managed files and safely deletes missing or existing files',
      () async {
        final source = await _writeFile(root, 'source.webp', [5, 6]);
        final fileName = await store.importFile(
          themeId: _themeId,
          source: source,
        );

        expect(await store.resolve(fileName), isNotNull);
        await store.delete(fileName);
        expect(await store.resolve(fileName), isNull);
        await store.delete(fileName);
      },
    );
  });
}

Future<File> _writeFile(
  Directory directory,
  String name,
  List<int> bytes,
) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}

Future<List<FileSystemEntity>> _managedFiles(Directory root) async {
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}theme_backgrounds',
  );
  if (!await directory.exists()) return [];
  return directory.list().toList();
}
