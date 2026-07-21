import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

abstract class WindowShowHotkeyPlatform {
  Future<bool> register(String shortcut, void Function() onPressed);
  Future<void> unregister(String shortcut);
}

class WindowShowHotkeyService {
  WindowShowHotkeyService({WindowShowHotkeyPlatform? platform})
    : _platform = platform ?? _HotkeyManagerPlatform();

  final WindowShowHotkeyPlatform _platform;
  String? _currentShortcut;

  String? get currentShortcut => _currentShortcut;

  Future<bool> replace(String shortcut, [void Function()? onPressed]) async {
    if (_currentShortcut == shortcut) return true;
    if (!await _platform.register(shortcut, onPressed ?? () {})) return false;
    final previousShortcut = _currentShortcut;
    _currentShortcut = shortcut;
    if (previousShortcut != null) await _platform.unregister(previousShortcut);
    return true;
  }

  Future<void> dispose() async {
    final shortcut = _currentShortcut;
    _currentShortcut = null;
    if (shortcut != null) await _platform.unregister(shortcut);
  }
}

class _HotkeyManagerPlatform implements WindowShowHotkeyPlatform {
  final Map<String, HotKey> _registered = {};

  @override
  Future<bool> register(String shortcut, void Function() onPressed) async {
    final hotKey = _parseShortcut(shortcut);
    try {
      await hotKeyManager.register(hotKey, keyDownHandler: (_) => onPressed());
      _registered[shortcut] = hotKey;
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> unregister(String shortcut) async {
    final hotKey = _registered.remove(shortcut);
    if (hotKey != null) await hotKeyManager.unregister(hotKey);
  }

  HotKey _parseShortcut(String shortcut) {
    final parts = shortcut.toLowerCase().split('+');
    final keyLabel = parts.last;
    final key = PhysicalKeyboardKey.knownPhysicalKeys.firstWhere(
      (candidate) => candidate.keyLabel.toLowerCase() == keyLabel,
    );
    final modifiers = <HotKeyModifier>[
      if (parts.contains('ctrl')) HotKeyModifier.control,
      if (parts.contains('alt')) HotKeyModifier.alt,
      if (parts.contains('shift')) HotKeyModifier.shift,
      if (parts.contains('win')) HotKeyModifier.meta,
    ];
    return HotKey(key: key, modifiers: modifiers, scope: HotKeyScope.system);
  }
}
