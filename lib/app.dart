import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/custom_theme.dart';
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
    this.initializeServices = true,
  });
  final BatteryController? controller;
  final TrayService? trayService;
  final bool initializeServices;

  @override
  State<AgentBatteryApp> createState() => _AgentBatteryAppState();
}

class _AgentBatteryAppState extends State<AgentBatteryApp> with WindowListener {
  late final BatteryController controller =
      widget.controller ??
      BatteryController(storage: StorageService(), api: ApiClient());
  late final TrayService tray = widget.trayService ?? TrayService();
  ThemeReference? _lastAppliedThemeReference;
  WindowLayoutPolicy? _lastAppliedLayout;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    if (!widget.initializeServices) return;
    windowManager.addListener(this);
    controller.initialize();
    tray.initialize();
  }

  void _changed() {
    if (widget.initializeServices && Platform.isWindows) {
      _applyThemeWindowLayout();
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
      WindowLayoutPolicy.transitionSize(currentSize: currentSize, target: policy),
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
      home: HomeScreen(controller: controller, onExitRequested: _exitApp),
    );
  }
}
