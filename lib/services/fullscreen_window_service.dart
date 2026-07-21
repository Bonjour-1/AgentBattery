import 'package:window_manager/window_manager.dart';

abstract class FullscreenWindowPlatform {
  Future<bool> isFullScreen();
  Future<bool> isMaximized();
  Future<void> maximize();
  Future<void> setFullScreen(bool value);
  Future<void> unmaximize();
}

class FullscreenWindowService {
  FullscreenWindowService({FullscreenWindowPlatform? platform})
    : _platform = platform ?? _WindowManagerFullscreenPlatform();

  final FullscreenWindowPlatform _platform;
  bool _restoreMaximized = false;

  Future<void> toggle() async {
    if (await _platform.isFullScreen()) {
      await exit();
      return;
    }
    _restoreMaximized = await _platform.isMaximized();
    if (_restoreMaximized) await _platform.unmaximize();
    await _platform.setFullScreen(true);
  }

  Future<void> exit() async {
    if (!await _platform.isFullScreen()) return;
    await _platform.setFullScreen(false);
    if (_restoreMaximized) await _platform.maximize();
    _restoreMaximized = false;
  }
}

class _WindowManagerFullscreenPlatform implements FullscreenWindowPlatform {
  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);

  @override
  Future<void> unmaximize() => windowManager.unmaximize();
}
