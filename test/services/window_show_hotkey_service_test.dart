import 'package:agent_battery_flutter/services/window_show_hotkey_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHotkeyPlatform implements WindowShowHotkeyPlatform {
  final registered = <String>[];
  final unregistered = <String>[];
  String? conflictingShortcut;

  @override
  Future<bool> register(String shortcut, void Function() onPressed) async {
    registered.add(shortcut);
    return shortcut != conflictingShortcut;
  }

  @override
  Future<void> unregister(String shortcut) async {
    unregistered.add(shortcut);
  }
}

void main() {
  test('keeps the prior system hotkey when a replacement collides', () async {
    final platform = FakeHotkeyPlatform();
    final service = WindowShowHotkeyService(platform: platform);

    expect(await service.replace('ctrl+alt+b'), isTrue);
    platform.conflictingShortcut = 'ctrl+alt+n';

    expect(await service.replace('ctrl+alt+n'), isFalse);
    expect(service.currentShortcut, 'ctrl+alt+b');
    expect(platform.unregistered, isEmpty);
  });
}
