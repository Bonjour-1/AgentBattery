import 'package:agent_battery_flutter/services/fullscreen_window_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFullscreenWindowPlatform implements FullscreenWindowPlatform {
  final calls = <String>[];
  bool fullScreen = false;
  bool maximized = false;

  @override
  Future<void> setFullScreen(bool value) async {
    calls.add('fullscreen:$value');
    fullScreen = value;
  }

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> maximize() async {
    calls.add('maximize');
    maximized = true;
  }

  @override
  Future<void> unmaximize() async {
    calls.add('unmaximize');
    maximized = false;
  }
}

void main() {
  test(
    'uses the native fullscreen transition without preemptively removing the frame',
    () async {
      final platform = FakeFullscreenWindowPlatform();
      final service = FullscreenWindowService(platform: platform);

      await service.toggle();

      expect(platform.calls, ['fullscreen:true']);
    },
  );

  test(
    'restores a maximized window before native fullscreen and maximizes it again on exit',
    () async {
      final platform = FakeFullscreenWindowPlatform()..maximized = true;
      final service = FullscreenWindowService(platform: platform);

      await service.toggle();
      await service.exit();

      expect(platform.calls, [
        'unmaximize',
        'fullscreen:true',
        'fullscreen:false',
        'maximize',
      ]);
    },
  );

  test('exits through the native fullscreen restore path', () async {
    final platform = FakeFullscreenWindowPlatform()..fullScreen = true;
    final service = FullscreenWindowService(platform: platform);

    await service.exit();

    expect(platform.calls, ['fullscreen:false']);
  });
}
