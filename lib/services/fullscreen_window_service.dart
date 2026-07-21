import 'package:window_manager/window_manager.dart';

abstract class FullscreenWindowPlatform {
  Future<bool> isFullScreen();
  Future<void> setFullScreen(bool value);
}

class FullscreenWindowService {
  FullscreenWindowService({FullscreenWindowPlatform? platform})
    : _platform = platform ?? _WindowManagerFullscreenPlatform();

  final FullscreenWindowPlatform _platform;

  Future<void> toggle() async {
    if (await _platform.isFullScreen()) {
      await exit();
      return;
    }
    await _platform.setFullScreen(true);
  }

  Future<void> exit() async {
    if (!await _platform.isFullScreen()) return;
    await _platform.setFullScreen(false);
  }
}

class _WindowManagerFullscreenPlatform implements FullscreenWindowPlatform {
  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullScreen(bool value) => windowManager.setFullScreen(value);
}
