import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models/custom_theme.dart';
import 'services/fullscreen_window_service.dart';
import 'services/window_show_hotkey_service.dart';
import 'services/api_client.dart';
import 'services/storage_service.dart';
import 'services/tray_service.dart';
import 'state/battery_controller.dart';
import 'ui/window_layout_policy.dart';
import 'ui/screens/home_screen.dart';

class AgentBatteryApp extends StatefulWidget {
  const AgentBatteryApp({
    super.key,
    this.controller,
    this.trayService,
    this.windowShowHotkeyService,
    this.fullscreenWindowService,
    this.initializeServices = true,
  });
  final BatteryController? controller;
  final TrayService? trayService;
  final WindowShowHotkeyService? windowShowHotkeyService;
  final FullscreenWindowService? fullscreenWindowService;
  final bool initializeServices;

  @override
  State<AgentBatteryApp> createState() => _AgentBatteryAppState();
}

class _AgentBatteryAppState extends State<AgentBatteryApp> with WindowListener {
  late final BatteryController controller =
      widget.controller ??
      BatteryController(storage: StorageService(), api: ApiClient());
  late final TrayService tray = widget.trayService ?? TrayService();
  late final WindowShowHotkeyService windowShowHotkey =
      widget.windowShowHotkeyService ?? WindowShowHotkeyService();
  late final FullscreenWindowService fullscreenWindow =
      widget.fullscreenWindowService ?? FullscreenWindowService();
  ThemeReference? _lastAppliedThemeReference;
  WindowLayoutPolicy? _lastAppliedLayout;
  Future<void> _windowLayoutUpdate = Future.value();

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    if (!widget.initializeServices) return;
    windowManager.addListener(this);
    controller.initialize().then((_) => _registerWindowShowHotkey());
    tray.initialize();
  }

  Future<bool> _registerWindowShowHotkey([String? shortcut]) => windowShowHotkey
      .replace(shortcut ?? controller.windowShowHotkey, () async {
        await windowManager.show();
        await windowManager.focus();
      });

  Future<void> _toggleFullscreen() => fullscreenWindow.toggle();

  Future<void> _exitFullscreen() => fullscreenWindow.exit();

  void _changed() {
    if (widget.initializeServices && Platform.isWindows) {
      _windowLayoutUpdate = _windowLayoutUpdate.then((_) async {
        await _applyThemeWindowLayout();
        await _registerWindowShowHotkey();
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _applyThemeWindowLayout() async {
    final reference = controller.themeReference;
    if (_lastAppliedThemeReference == reference) return;
    _lastAppliedThemeReference = reference;
    final policy = controller.resolvedTheme.layout;
    final previousLayout = _lastAppliedLayout;
    _lastAppliedLayout = policy;
    await windowManager.setMinimumSize(policy.minimumSize);
    if (!WindowLayoutPolicy.shouldTransition(
      previous: previousLayout,
      target: policy,
    )) {
      return;
    }
    final currentSize = await windowManager.getSize();
    await windowManager.setSize(
      WindowLayoutPolicy.transitionSize(
        currentSize: currentSize,
        target: policy,
      ),
    );
  }

  Future<void> _exitApp() => tray.exitApp();

  @override
  void onWindowClose() {
    if (tray.ready) {
      windowManager.hide();
    }
  }

  @override
  void dispose() {
    if (widget.initializeServices) windowManager.removeListener(this);
    controller.removeListener(_changed);
    controller.dispose();
    if (widget.initializeServices) windowShowHotkey.dispose();
    if (widget.initializeServices) tray.disposeTray();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = controller.resolvedTheme.tokens;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AgentBattery',
      theme: tokens.materialTheme(),
      themeAnimationDuration:
          MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : const Duration(milliseconds: 320),
      themeAnimationCurve: Curves.easeInOutCubicEmphasized,
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
          const SingleActivator(LogicalKeyboardKey.escape): _exitFullscreen,
        },
        child: Focus(
          autofocus: true,
          child: HomeScreen(
            controller: controller,
            onExitRequested: _exitApp,
            onWindowShowHotkeyRegistration: _registerWindowShowHotkey,
          ),
        ),
      ),
    );
  }
}
