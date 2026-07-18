import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener {
  bool ready = false;

  Future<bool> initialize() async {
    if (!Platform.isWindows) return false;
    try {
      await trayManager.setIcon(r'windows\runner\resources\app_icon.ico');
      await trayManager.setToolTip('AgentBattery');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'toggle', label: '显示/隐藏'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: '退出'),
          ],
        ),
      );
      trayManager.addListener(this);
      ready = true;
      await windowManager.setPreventClose(true);
      return true;
    } catch (_) {
      ready = false;
      return false;
    }
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'toggle') {
      _toggle();
    } else if (menuItem.key == 'exit') {
      exitApp();
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _toggle() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await _show();
    }
  }

  Future<void> exitApp() async {
    final wasReady = ready;
    ready = false;
    await windowManager.setPreventClose(false);
    trayManager.removeListener(this);
    if (wasReady) await trayManager.destroy();
    await windowManager.destroy();
  }

  Future<void> disposeTray() async {
    trayManager.removeListener(this);
    final wasReady = ready;
    ready = false;
    if (wasReady) await trayManager.destroy();
  }
}
