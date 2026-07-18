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
  Future<void> pumpMiku(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final controller = BatteryController(
      storage: StorageService(),
      api: ApiClient(),
    );
    await controller.selectTheme(AppTheme.miku);
    await tester.pumpWidget(
      AgentBatteryApp(controller: controller, initializeServices: false),
    );
    await tester.pump();
  }

  test('MIKU stage policy reserves a wider right-side character zone', () {
    expect(WindowLayoutPolicy.mikuStage.size, const Size(1320, 760));
    expect(WindowLayoutPolicy.mikuStage.minimumSize, const Size(1080, 680));
  });

  testWidgets('builds the MIKU horizontal stage at desktop width', (
    tester,
  ) async {
    await pumpMiku(tester, const Size(1320, 760));

    expect(find.byKey(const ValueKey('miku-stage-wide')), findsOneWidget);
    expect(find.text('AGENT BATTERY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the MIKU compact flow without overflow below 920 pixels', (
    tester,
  ) async {
    await pumpMiku(tester, const Size(700, 760));

    expect(find.byKey(const ValueKey('miku-stage-compact')), findsOneWidget);
    expect(find.text('AGENT BATTERY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
