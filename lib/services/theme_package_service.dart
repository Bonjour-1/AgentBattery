import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../models/custom_theme.dart';

typedef ThemePackageTemporaryDirectoryProvider = Future<Directory> Function();

class ThemePackageException implements Exception {
  ThemePackageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'ThemePackageException: $message';
}

class ImportedThemePackage {
  ImportedThemePackage({
    required this.theme,
    required this.background,
    required this.backgroundExtension,
  });

  final CustomTheme theme;
  final File? background;
  final String? backgroundExtension;

  Future<void> dispose() async {
    final file = background;
    if (file != null && await file.exists()) await file.delete();
  }
}

class ThemePackageService {
  ThemePackageService({
    ThemePackageTemporaryDirectoryProvider? temporaryDirectory,
  }) : _temporaryDirectory =
           temporaryDirectory ?? Directory.systemTemp.createTemp;

  static const schema = 'agentbattery-theme';
  static const version = 1;
  static const maxPackageSizeBytes = 20 * 1024 * 1024;
  static const maxBackgroundSizeBytes = 15 * 1024 * 1024;
  static const _manifestEntry = 'manifest.json';
  static const _allowedBackgroundExtensions = {'png', 'jpg', 'jpeg', 'webp'};

  final ThemePackageTemporaryDirectoryProvider _temporaryDirectory;

  Future<File> exportTheme(
    CustomTheme theme, {
    required File destination,
    File? background,
  }) async {
    final backgroundExtension = background == null
        ? null
        : _extensionOf(background.path);
    if (background != null) {
      if (!_allowedBackgroundExtensions.contains(backgroundExtension)) {
        throw ThemePackageException(
          'Background image must be a PNG, JPG, JPEG, or WEBP file.',
        );
      }
      final length = await _fileLength(
        background,
        'Could not read the background image.',
      );
      if (length > maxBackgroundSizeBytes) {
        throw ThemePackageException('Background image must not exceed 15 MB.');
      }
    }
    if ((theme.backgroundImageFileName == null) != (background == null)) {
      throw ThemePackageException(
        'Theme background metadata and image must be supplied together.',
      );
    }

    final manifest = <String, Object?>{
      'schema': schema,
      'version': version,
      'theme': _portableThemeJson(theme),
      if (background != null) ...{
        'background_entry': 'background.$backgroundExtension',
        'background_extension': backgroundExtension,
      },
    };
    final archive = Archive()
      ..addFile(
        ArchiveFile(_manifestEntry, 0, utf8.encode(jsonEncode(manifest))),
      );
    if (background != null) {
      final bytes = await background.readAsBytes();
      archive.addFile(
        ArchiveFile('background.$backgroundExtension', bytes.length, bytes),
      );
    }

    final temporary = File('${destination.path}.tmp');
    try {
      final bytes = ZipEncoder().encodeBytes(archive);
      if (bytes.length > maxPackageSizeBytes) {
        throw ThemePackageException('Theme package must not exceed 20 MB.');
      }
      await temporary.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
      return destination;
    } on ThemePackageException {
      await _deleteIfPresent(temporary);
      rethrow;
    } on Object catch (error) {
      await _deleteIfPresent(temporary);
      throw ThemePackageException('Could not export the theme package.', error);
    }
  }

  Future<ImportedThemePackage> readPackage(File source) async {
    final length = await _fileLength(
      source,
      'Could not read the theme package.',
    );
    if (length > maxPackageSizeBytes) {
      throw ThemePackageException('Theme package must not exceed 20 MB.');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(
        await source.readAsBytes(),
        verify: true,
      );
    } on Object catch (error) {
      throw ThemePackageException(
        'Theme package is not a valid ZIP archive.',
        error,
      );
    }
    final files = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      if (entry.isDirectory ||
          !_isSafeEntryName(entry.name) ||
          files.containsKey(entry.name)) {
        throw ThemePackageException(
          'Theme package contains an unsafe or duplicate entry.',
        );
      }
      files[entry.name] = entry;
    }
    final manifestFile = files[_manifestEntry];
    if (manifestFile == null) {
      throw ThemePackageException('Theme package is missing manifest.json.');
    }

    final manifest = _decodeManifest(manifestFile);
    final backgroundEntry = manifest['background_entry'];
    final backgroundExtension = manifest['background_extension'];
    final expectedEntries = <String>{_manifestEntry};
    String? validBackgroundEntry;
    String? validBackgroundExtension;
    if (backgroundEntry != null || backgroundExtension != null) {
      if (backgroundEntry is! String ||
          backgroundExtension is! String ||
          backgroundEntry != 'background.$backgroundExtension' ||
          !_allowedBackgroundExtensions.contains(backgroundExtension)) {
        throw ThemePackageException(
          'Theme package background metadata is invalid.',
        );
      }
      validBackgroundEntry = backgroundEntry;
      validBackgroundExtension = backgroundExtension;
      expectedEntries.add(validBackgroundEntry);
    }
    if (files.keys.toSet().difference(expectedEntries).isNotEmpty ||
        expectedEntries.difference(files.keys.toSet()).isNotEmpty) {
      throw ThemePackageException(
        'Theme package contains missing or unknown entries.',
      );
    }

    final theme = _decodeTheme(manifest['theme']);
    if (validBackgroundEntry == null) {
      return ImportedThemePackage(
        theme: theme,
        background: null,
        backgroundExtension: null,
      );
    }
    final resolvedBackgroundEntry = validBackgroundEntry;
    final backgroundBytes = _contents(files[resolvedBackgroundEntry]!);
    if (backgroundBytes.length > maxBackgroundSizeBytes) {
      throw ThemePackageException(
        'Theme package background must not exceed 15 MB.',
      );
    }
    final directory = await _temporaryDirectory();
    await directory.create(recursive: true);
    final background = File(
      '${directory.path}${Platform.pathSeparator}'
      'imported-background.$validBackgroundExtension',
    );
    try {
      await background.writeAsBytes(backgroundBytes, flush: true);
      return ImportedThemePackage(
        theme: theme,
        background: background,
        backgroundExtension: validBackgroundExtension,
      );
    } on Object catch (error) {
      await _deleteIfPresent(background);
      throw ThemePackageException(
        'Could not prepare the imported background image.',
        error,
      );
    }
  }

  static Map<String, Object?> _portableThemeJson(CustomTheme theme) {
    final json = Map<String, Object?>.from(theme.toJson())
      ..remove('background_image_file_name');
    return json;
  }

  static Map<String, Object?> _decodeManifest(ArchiveFile file) {
    try {
      final value = jsonDecode(utf8.decode(_contents(file)));
      if (value is! Map) throw const FormatException();
      final manifest = Map<String, Object?>.from(value);
      const allowed = {
        'schema',
        'version',
        'theme',
        'background_entry',
        'background_extension',
      };
      if (manifest.keys.any((key) => !allowed.contains(key)) ||
          manifest['schema'] != schema ||
          manifest['version'] != version) {
        throw const FormatException();
      }
      return manifest;
    } on Object catch (error) {
      throw ThemePackageException('Theme package manifest is invalid.', error);
    }
  }

  static CustomTheme _decodeTheme(Object? value) {
    try {
      if (value is! Map) throw const FormatException();
      final json = Map<String, Object?>.from(value);
      const allowed = {
        'id',
        'name',
        'layout',
        'palette',
        'card_radius',
        'control_radius',
        'content_radius',
        'shadow_opacity',
        'stage_overlay_opacity',
        'stage_gradient_secondary',
        'stage_gradient_direction',
        'content_gradient_secondary',
        'content_gradient_direction',
        'card_gradient_secondary',
        'card_gradient_direction',
        'dashboard_layout_mode',
        'dashboard_density',
        'background_image_fit',
        'background_image_alignment',
        'background_image_opacity',
      };
      if (json.keys.any((key) => !allowed.contains(key)) ||
          json.containsKey('background_image_file_name')) {
        throw const FormatException();
      }
      return CustomTheme.fromJson(json);
    } on Object catch (error) {
      throw ThemePackageException(
        'Theme package theme data is invalid.',
        error,
      );
    }
  }

  static List<int> _contents(ArchiveFile file) => List<int>.from(file.content);

  static bool _isSafeEntryName(String value) =>
      value.isNotEmpty &&
      !value.startsWith('/') &&
      !value.startsWith(r'\') &&
      !RegExp(r'^[a-zA-Z]:').hasMatch(value) &&
      !value.split('/').contains('..') &&
      !value.contains(r'\');

  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static Future<int> _fileLength(File file, String message) async {
    try {
      return await file.length();
    } on Object catch (error) {
      throw ThemePackageException(message, error);
    }
  }

  static Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // Cleanup must not hide the original export or import failure.
    }
  }
}
