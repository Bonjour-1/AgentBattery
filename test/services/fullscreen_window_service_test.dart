import 'package:agent_battery_flutter/services/fullscreen_window_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFullscreenWindowPlatform implements FullscreenWindowPlatform {
  final calls = <String>[];
  bool fullScreen = false;

  @override
  Future<void> setFullScreen(bool value) async {
    calls.add('fullscreen:$value');
    fullScreen = value;
  }

  @override
  Future<bool> isFullScreen() async => fullScreen;
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

  test('exits through the native fullscreen restore path', () async {
    final platform = FakeFullscreenWindowPlatform()..fullScreen = true;
    final service = FullscreenWindowService(platform: platform);

    await service.exit();

    expect(platform.calls, ['fullscreen:false']);
  });
}
