import 'package:agent_battery_flutter/app.dart';
import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:agent_battery_flutter/ui/window_layout_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpMita(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final controller = BatteryController(
      storage: StorageService(),
      api: ApiClient(),
    );
    await controller.selectTheme(AppTheme.mita);
    await tester.pumpWidget(
      AgentBatteryApp(controller: controller, initializeServices: false),
    );
    await tester.pump();
  }

  test('Mita uses the horizontal character-stage window policy', () {
    final policy = WindowLayoutPolicy.forTheme(AppTheme.mita);

    expect(policy.size, const Size(1320, 760));
    expect(policy.minimumSize, const Size(1080, 680));
  });

  testWidgets('builds the Mita horizontal stage with its approved copy', (
    tester,
  ) async {
    await pumpMita(tester, const Size(1320, 760));

    expect(find.byKey(const ValueKey('mita-stage-wide')), findsOneWidget);
    expect(find.text('AGENT BATTERY · MITA'), findsOneWidget);
    expect(find.text('彩铅小屋里的 AI 能量记录册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the Mita compact flow without overflow below 920 pixels', (
    tester,
  ) async {
    await pumpMita(tester, const Size(700, 760));

    expect(find.byKey(const ValueKey('mita-stage-compact')), findsOneWidget);
    expect(find.text('AGENT BATTERY · MITA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
