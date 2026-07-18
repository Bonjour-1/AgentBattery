import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

typedef AppSupportDirectoryProvider = Future<Directory> Function();

abstract interface class ThemeBackgroundService {
  Future<void> delete(String fileName);
  Future<String> importFile({required String themeId, required File source});
  Future<File?> resolve(String fileName);
}

class ThemeBackgroundStoreException implements Exception {
  ThemeBackgroundStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'ThemeBackgroundStoreException: $message';
}

class ThemeBackgroundStore implements ThemeBackgroundService {
  ThemeBackgroundStore({AppSupportDirectoryProvider? appSupportDirectory})
    : _appSupportDirectory =
          appSupportDirectory ?? getApplicationSupportDirectory;

  static const maxFileSizeBytes = 15 * 1024 * 1024;
  static const _directoryName = 'theme_backgrounds';
  static const _allowedExtensions = {'png', 'jpg', 'jpeg', 'webp'};

  final AppSupportDirectoryProvider _appSupportDirectory;

  @override
  Future<String> importFile({required String themeId, required File source}) =>
      _import(
        sourcePath: source.path,
        themeId: themeId,
        copySource: (destination) async {
          await source.copy(destination.path);
        },
      );

  Future<String> importXFile({
    required String themeId,
    required XFile source,
  }) => _import(
    sourcePath: source.name,
    themeId: themeId,
    copySource: (destination) => source.saveTo(destination.path),
    sourceLength: source.length,
  );

  Future<String> _import({
    required String themeId,
    required String sourcePath,
    required Future<void> Function(File destination) copySource,
    Future<int> Function()? sourceLength,
  }) async {
    final extension = _extensionOf(sourcePath);
    if (!_allowedExtensions.contains(extension)) {
      throw ThemeBackgroundStoreException(
        'Background image must be a PNG, JPG, JPEG, or WEBP file.',
      );
    }

    int size;
    try {
      size = await (sourceLength?.call() ?? File(sourcePath).length());
    } on ThemeBackgroundStoreException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ThemeBackgroundStoreException(
        'Could not read the background image source.',
        error,
      );
    }
    if (size > maxFileSizeBytes) {
      throw ThemeBackgroundStoreException(
        'Background image must not exceed 15 MB.',
      );
    }

    final fileName = '$themeId-${_randomUuid()}.$extension';
    final destination = await _newDestinationFor(fileName);
    try {
      await copySource(destination);
      return fileName;
    } on FileSystemException catch (error) {
      await _deleteIfPresent(destination);
      throw ThemeBackgroundStoreException(
        'Could not import the background image.',
        error,
      );
    }
  }

  @override
  Future<File?> resolve(String fileName) async {
    final file = await _fileFor(fileName);
    return await file.exists() ? file : null;
  }

  @override
  Future<void> delete(String fileName) async {
    final file = await _fileFor(fileName);
    await _deleteIfPresent(file);
  }

  Future<File> _newDestinationFor(String fileName) async {
    _validateBasename(fileName);
    final root = await _appSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}$_directoryName',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  Future<File> _fileFor(String fileName) async {
    _validateBasename(fileName);
    final root = await _appSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}$_directoryName',
    );
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      throw ThemeBackgroundStoreException(
        'Could not delete the background image.',
        error,
      );
    }
  }

  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static void _validateBasename(String value) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains(r'\') ||
        value.startsWith(Platform.pathSeparator)) {
      throw ArgumentError.value(
        value,
        'fileName',
        'must be a managed basename',
      );
    }
  }

  static String _randomUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
